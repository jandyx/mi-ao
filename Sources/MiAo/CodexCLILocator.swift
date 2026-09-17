// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import AppKit
import Foundation

struct ProcessTableEntry: Equatable, Sendable {
    let pid: pid_t
    let ppid: pid_t
    /// `/dev/ttysNNN`；无控制终端时为 nil。
    let tty: String?
    let command: String

    var commandName: String {
        URL(fileURLWithPath: command).lastPathComponent
    }
}

struct TmuxPane: Equatable, Sendable {
    let id: String
    let tty: String
    let session: String
    let windowIndex: Int
    let paneActive: Bool
    let windowActive: Bool
    let sessionAttached: Bool

    static let listFormat =
        "#{pane_id}\t#{pane_tty}\t#{session_name}\t#{window_index}\t#{pane_active}\t#{window_active}\t#{session_attached}"
}

struct RunningApplicationInfo: Equatable, Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let isRegular: Bool
    let isActive: Bool

    init(
        pid: pid_t,
        bundleIdentifier: String?,
        localizedName: String?,
        isRegular: Bool,
        isActive: Bool
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isRegular = isRegular
        self.isActive = isActive
    }

    init?(_ application: NSRunningApplication?) {
        guard let application else { return nil }
        self.init(
            pid: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            isRegular: application.activationPolicy == .regular,
            isActive: application.isActive
        )
    }
}

struct CommandResult: Equatable, Sendable {
    let exitCode: Int32
    let output: String

    var succeeded: Bool { exitCode == 0 }
}

enum ExternalCommand {
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) -> CommandResult? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return nil
        }
        let reader = output.fileHandleForReading
        let collected = DispatchQueue.global(qos: .userInitiated)
        let box = OutputBox()
        let finished = DispatchSemaphore(value: 0)
        collected.async {
            box.data = reader.readDataToEndOfFile()
            finished.signal()
        }
        let deadline = DispatchTime.now() + timeout
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            return nil
        }
        process.waitUntilExit()
        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(data: box.data, encoding: .utf8) ?? ""
        )
    }

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }
}

struct CodexCLIRuntime: Sendable {
    var runCommand: @Sendable (URL, [String], TimeInterval) -> CommandResult?
    var runningApplication: @Sendable (pid_t) -> RunningApplicationInfo?
    var runningApplications: @Sendable (String) -> [RunningApplicationInfo]
    var isExecutable: @Sendable (String) -> Bool
    var listDirectory: @Sendable (String) -> [String]
    var readFile: @Sendable (String) -> Data?
    var homeDirectory: String
    var environment: [String: String]

    static let live = CodexCLIRuntime(
        runCommand: { executable, arguments, timeout in
            ExternalCommand.run(
                executable: executable,
                arguments: arguments,
                environment: MiAoProcessEnvironment.sanitizedForExternalProcess(),
                timeout: timeout
            )
        },
        runningApplication: { pid in
            RunningApplicationInfo(NSRunningApplication(processIdentifier: pid))
        },
        runningApplications: { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .compactMap { RunningApplicationInfo($0) }
        },
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        listDirectory: { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] },
        readFile: { FileManager.default.contents(atPath: $0) },
        homeDirectory: NSHomeDirectory(),
        environment: ProcessInfo.processInfo.environment
    )

    var tmuxExecutable: URL? {
        TerminalCatalog.tmuxCandidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    @discardableResult
    func tmux(_ arguments: [String], timeout: TimeInterval = 3) -> CommandResult? {
        guard let tmuxExecutable else { return nil }
        return runCommand(tmuxExecutable, arguments, timeout)
    }
}

enum CodexCLIProcessTable {
    static let psArguments = ["-axo", "pid=,ppid=,tty=,comm="]

    static func parse(_ output: String) -> [ProcessTableEntry] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let fields = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = pid_t(fields[0]), let ppid = pid_t(fields[1]) else {
                return nil
            }
            let ttyField = String(fields[2])
            let tty: String? = ttyField.hasPrefix("tty") ? "/dev/" + ttyField : nil
            return ProcessTableEntry(
                pid: pid,
                ppid: ppid,
                tty: tty,
                command: fields[3].trimmingCharacters(in: .whitespaces)
            )
        }
    }

    static func isCodexCLI(command: String) -> Bool {
        let name = URL(fileURLWithPath: command).lastPathComponent
        if name == "codex" { return true }
        return name.hasPrefix("codex-") && name.hasSuffix("-apple-darwin")
    }

    static func ancestors(of pid: pid_t, in table: [ProcessTableEntry]) -> [ProcessTableEntry] {
        let byPID = Dictionary(table.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var visited: Set<pid_t> = [pid]
        var chain: [ProcessTableEntry] = []
        var current = byPID[pid]?.ppid
        while let pid = current, pid > 1, !visited.contains(pid), let entry = byPID[pid] {
            visited.insert(pid)
            chain.append(entry)
            current = entry.ppid
        }
        return chain
    }

    static func resolvedTTY(of pid: pid_t, in table: [ProcessTableEntry]) -> String? {
        if let own = table.first(where: { $0.pid == pid })?.tty { return own }
        return ancestors(of: pid, in: table).first { $0.tty != nil }?.tty
    }

    static func isInsideTmux(pid: pid_t, in table: [ProcessTableEntry]) -> Bool {
        ancestors(of: pid, in: table).contains { $0.commandName == "tmux" }
    }

    static func parseTmuxPanes(_ output: String) -> [TmuxPane] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7, let windowIndex = Int(fields[3]) else { return nil }
            return TmuxPane(
                id: fields[0],
                tty: fields[1],
                session: fields[2],
                windowIndex: windowIndex,
                paneActive: fields[4] == "1",
                windowActive: fields[5] == "1",
                sessionAttached: fields[6] != "0"
            )
        }
    }

    static func rank(_ pane: TmuxPane) -> Int {
        if pane.sessionAttached && pane.paneActive && pane.windowActive { return 0 }
        if pane.sessionAttached { return 1 }
        return 2
    }

    static func preferredPane(_ panes: [TmuxPane]) -> TmuxPane? {
        panes.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs.element)
                let rhsRank = rank(rhs.element)
                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .first?.element
    }
}

struct CodexCLITarget: Equatable, Sendable {
    enum Transport: Equatable, Sendable {
        case tmux(paneID: String, session: String)
        case terminalApp(bundleIdentifier: String, pid: pid_t, name: String)
    }

    let codexPID: pid_t
    let tty: String?
    let transport: Transport
    /// tmux 窗格所在 session 当前 attach 在哪个终端 App（无 client 时为 nil）。
    let hostBundleIdentifier: String?
    let hostName: String?

    init(
        codexPID: pid_t,
        tty: String?,
        transport: Transport,
        hostBundleIdentifier: String? = nil,
        hostName: String? = nil
    ) {
        self.codexPID = codexPID
        self.tty = tty
        self.transport = transport
        self.hostBundleIdentifier = hostBundleIdentifier
        self.hostName = hostName
    }

    var description: String {
        switch transport {
        case .tmux(let paneID, let session):
            let host = hostName.map { " · \($0)" } ?? " · 未 attach"
            return "tmux \(paneID) · session \(session)\(host)"
        case .terminalApp(_, let pid, let name):
            return "\(name) · pid \(pid)"
        }
    }

    var terminalName: String {
        switch transport {
        case .tmux: return "tmux"
        case .terminalApp(_, _, let name): return name
        }
    }

    func matches(choice: CodexCLITerminalChoice) -> Bool {
        switch (choice, transport) {
        case (.auto, _):
            return true
        case (.tmux, .tmux):
            return true
        case (.app(let wanted), .terminalApp(let bundleIdentifier, _, _)):
            return wanted == bundleIdentifier
        case (.app(let wanted), .tmux):
            // 选了某个终端 App 时，attach 在该终端里的 tmux 会话同样算“在这个终端里”。
            return wanted == hostBundleIdentifier
        default:
            return false
        }
    }
}

struct CodexCLILocator: Sendable {
    let runtime: CodexCLIRuntime

    init(runtime: CodexCLIRuntime = .live) {
        self.runtime = runtime
    }

    func processTable() -> [ProcessTableEntry] {
        guard
            let result = runtime.runCommand(
                URL(fileURLWithPath: "/bin/ps"),
                CodexCLIProcessTable.psArguments,
                3
            ),
            result.succeeded
        else { return [] }
        return CodexCLIProcessTable.parse(result.output)
    }

    /// nil 表示 tmux 不可用或服务未运行。
    func tmuxPanes() -> [TmuxPane]? {
        guard let result = runtime.tmux(["list-panes", "-a", "-F", TmuxPane.listFormat]), result.succeeded
        else { return nil }
        return CodexCLIProcessTable.parseTmuxPanes(result.output)
    }

    func locate(choice: CodexCLITerminalChoice = .auto) -> [CodexCLITarget] {
        let table = processTable()
        let codexProcesses = table.filter { CodexCLIProcessTable.isCodexCLI(command: $0.command) }
        guard !codexProcesses.isEmpty else { return [] }
        let panes = tmuxPanes() ?? []

        var ranked: [(target: CodexCLITarget, rank: Int)] = []
        var sessionHosts: [String: RunningApplicationInfo?] = [:]
        for process in codexProcesses {
            let tty = CodexCLIProcessTable.resolvedTTY(of: process.pid, in: table)
            if let tty, let pane = panes.first(where: { $0.tty == tty }) {
                let host: RunningApplicationInfo?
                if let cached = sessionHosts[pane.session] {
                    host = cached
                } else {
                    host = pane.sessionAttached ? tmuxClientHost(session: pane.session, in: table) : nil
                    sessionHosts[pane.session] = host
                }
                ranked.append(
                    (
                        CodexCLITarget(
                            codexPID: process.pid,
                            tty: tty,
                            transport: .tmux(paneID: pane.id, session: pane.session),
                            hostBundleIdentifier: host?.bundleIdentifier,
                            hostName: host.map {
                                TerminalCatalog.app(for: $0.bundleIdentifier ?? "", localizedName: $0.localizedName)
                                    .displayName
                            }
                        ),
                        CodexCLIProcessTable.rank(pane)
                    )
                )
                continue
            }
            guard let host = hostApplication(of: process.pid, in: table) else { continue }
            ranked.append(
                (
                    CodexCLITarget(
                        codexPID: process.pid,
                        tty: tty,
                        transport: .terminalApp(
                            bundleIdentifier: host.bundleIdentifier ?? "",
                            pid: host.pid,
                            name: TerminalCatalog.app(
                                for: host.bundleIdentifier ?? "",
                                localizedName: host.localizedName
                            ).displayName
                        ),
                        hostBundleIdentifier: host.bundleIdentifier,
                        hostName: TerminalCatalog.app(
                            for: host.bundleIdentifier ?? "",
                            localizedName: host.localizedName
                        ).displayName
                    ),
                    host.isActive ? 3 : 4
                )
            )
        }
        return
            ranked
            .filter { $0.target.matches(choice: choice) }
            .sorted { lhs, rhs in
                lhs.rank == rhs.rank ? lhs.target.codexPID < rhs.target.codexPID : lhs.rank < rhs.rank
            }
            .map(\.target)
    }

    /// 沿父进程链向上找第一个常规（有 Dock 图标）的 App；
    /// 遇到 iTermServer 这类终端守护进程时，映射回对应终端 App。
    func hostApplication(of pid: pid_t, in table: [ProcessTableEntry]) -> RunningApplicationInfo? {
        for ancestor in CodexCLIProcessTable.ancestors(of: pid, in: table) {
            if let application = runtime.runningApplication(ancestor.pid), application.isRegular,
                application.bundleIdentifier != nil
            {
                return application
            }
            if let bundleIdentifier = TerminalCatalog.hostBundleIdentifier(forHelperCommand: ancestor.command),
                let application = runtime.runningApplications(bundleIdentifier).first(where: \.isRegular)
                    ?? runtime.runningApplications(bundleIdentifier).first
            {
                return application
            }
        }
        return nil
    }

    /// 承载 tmux session 的终端 App（通过 attached client 的 tty 反查）。
    func tmuxClientHost(session: String, in table: [ProcessTableEntry]? = nil) -> RunningApplicationInfo? {
        guard let result = runtime.tmux(["list-clients", "-F", "#{client_tty}\t#{session_name}"]),
            result.succeeded
        else { return nil }
        let clientTTYs =
            result.output
            .split(separator: "\n")
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.count == 2 && $0[1] == session }
            .map(\.[0])
        guard !clientTTYs.isEmpty else { return nil }
        let table = table ?? processTable()
        for entry in table where entry.tty.map(clientTTYs.contains) == true {
            if let application = runtime.runningApplication(entry.pid), application.isRegular {
                return application
            }
            if let host = hostApplication(of: entry.pid, in: table) {
                return host
            }
        }
        return nil
    }
}

struct CodexCLIStatus: Equatable, Sendable {
    enum Login: Equatable, Sendable {
        case chatGPT
        case apiKey
        case notLoggedIn
        case unknown(String)

        var isLoggedIn: Bool {
            switch self {
            case .chatGPT, .apiKey: return true
            case .notLoggedIn, .unknown: return false
            }
        }

        var description: String {
            switch self {
            case .chatGPT: return "已登录（ChatGPT）"
            case .apiKey: return "已登录（API Key）"
            case .notLoggedIn: return "未登录"
            case .unknown(let detail): return "登录状态未知（\(detail)）"
            }
        }
    }

    let executable: String?
    let version: String?
    let login: Login
    let running: [CodexCLITarget]

    var isInstalled: Bool { executable != nil }

    var versionDescription: String {
        version.map { "Codex CLI \($0)" } ?? "Codex CLI"
    }
}

struct CodexCLIStatusInspector: Sendable {
    let runtime: CodexCLIRuntime

    init(runtime: CodexCLIRuntime = .live) {
        self.runtime = runtime
    }

    static func parseVersion(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" }).last else {
            return nil
        }
        let version = String(last)
        return version.first?.isNumber == true ? version : nil
    }

    static func parseLoginStatus(exitCode: Int32, output: String) -> CodexCLIStatus.Login {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("not logged in") { return .notLoggedIn }
        if normalized.contains("logged in") {
            if normalized.contains("api key") { return .apiKey }
            if normalized.contains("chatgpt") { return .chatGPT }
            return .unknown(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard exitCode == 0 else { return .notLoggedIn }
        return .unknown(normalized.isEmpty ? "无输出" : output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func loginFromAuthFile(_ data: Data) -> CodexCLIStatus.Login {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .notLoggedIn
        }
        let tokens = object["tokens"] as? [String: Any]
        let hasAccessToken = !((tokens?["access_token"] as? String) ?? "").isEmpty
        let hasAPIKey = !((object["OPENAI_API_KEY"] as? String) ?? "").isEmpty
        switch (object["auth_mode"] as? String)?.lowercased() {
        case "chatgpt" where hasAccessToken:
            return .chatGPT
        case "apikey" where hasAPIKey:
            return .apiKey
        default:
            if hasAccessToken { return .chatGPT }
            if hasAPIKey { return .apiKey }
            return .notLoggedIn
        }
    }

    func codexExecutableCandidates() -> [String] {
        let home = runtime.homeDirectory
        var candidates: [String] = []
        if let path = runtime.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }
        candidates += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.volta/bin/codex",
        ]
        let nvmRoot = "\(home)/.nvm/versions/node"
        candidates += runtime.listDirectory(nvmRoot).sorted(by: >).map { "\(nvmRoot)/\($0)/bin/codex" }
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    func resolvedExecutable() -> String? {
        codexExecutableCandidates().first(where: runtime.isExecutable)
    }

    var authFilePath: String {
        let codexHome = runtime.environment["CODEX_HOME"] ?? "\(runtime.homeDirectory)/.codex"
        return "\(codexHome)/auth.json"
    }

    func inspect(choice: CodexCLITerminalChoice = .auto) -> CodexCLIStatus {
        let executable = resolvedExecutable()
        var version: String?
        var login: CodexCLIStatus.Login = .notLoggedIn
        if let executable {
            let url = URL(fileURLWithPath: executable)
            if let result = runtime.runCommand(url, ["--version"], 3), result.succeeded {
                version = Self.parseVersion(result.output)
            }
            if let result = runtime.runCommand(url, ["login", "status"], 3) {
                login = Self.parseLoginStatus(exitCode: result.exitCode, output: result.output)
            } else if let data = runtime.readFile(authFilePath) {
                login = Self.loginFromAuthFile(data)
            }
        } else if let data = runtime.readFile(authFilePath) {
            login = Self.loginFromAuthFile(data)
        }
        return CodexCLIStatus(
            executable: executable,
            version: version,
            login: login,
            running: CodexCLILocator(runtime: runtime).locate(choice: choice)
        )
    }
}
