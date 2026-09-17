// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import AppKit
import Foundation

enum CodexCLITerminalChoice: Equatable, Sendable, RawRepresentable {
    case auto
    case tmux
    case app(String)

    private static let appPrefix = "app:"

    init?(rawValue: String) {
        switch rawValue {
        case "auto":
            self = .auto
        case "tmux":
            self = .tmux
        default:
            guard rawValue.hasPrefix(Self.appPrefix) else { return nil }
            let bundleIdentifier = String(rawValue.dropFirst(Self.appPrefix.count))
            guard !bundleIdentifier.isEmpty else { return nil }
            self = .app(bundleIdentifier)
        }
    }

    var rawValue: String {
        switch self {
        case .auto: return "auto"
        case .tmux: return "tmux"
        case .app(let bundleIdentifier): return Self.appPrefix + bundleIdentifier
        }
    }

    var displayName: String {
        switch self {
        case .auto: return "自动探测"
        case .tmux: return "tmux"
        case .app(let bundleIdentifier):
            return TerminalCatalog.app(for: bundleIdentifier).displayName
        }
    }
}

struct TerminalApp: Equatable, Sendable {
    enum LaunchStrategy: Equatable, Sendable {
        /// Terminal.app / iTerm2 支持用 AppleScript 在新窗口执行命令。
        case appleScript(TerminalScript)
        /// `open -na <App> --args <arguments…> <command…>`。
        case openWithArguments([String])
        /// 只激活 App，由用户自行输入命令。
        case focusOnly
    }

    enum TerminalScript: Equatable, Sendable {
        case terminal
        case iTerm
    }

    let bundleIdentifier: String
    let displayName: String
    let launch: LaunchStrategy

    /// 用用户自己的登录 shell 以交互模式执行一行命令：`-l` 读 profile 拿到 PATH，`-i` 读 rc 拿到 alias。
    /// iTerm2 / `open --args` 直接 exec、不搜 PATH，所以所有终端统一包这一层。
    static func shellInvocation(commandLine: String, shell: String) -> [String] {
        [shell, "-lic", commandLine]
    }

    /// 生成在该终端里执行 `commandLine` 的外部进程调用。返回 nil 表示只能聚焦。
    func launchInvocation(commandLine: String, shell: String) -> (executable: URL, arguments: [String])? {
        let shellWrapped = Self.shellInvocation(commandLine: commandLine, shell: shell)
        let wrappedLine = shellWrapped.map(Self.shellQuote).joined(separator: " ")
        switch launch {
        case .appleScript(.terminal):
            let script = """
                tell application "Terminal"
                    activate
                    do script \(Self.appleScriptQuote(wrappedLine))
                end tell
                """
            return (URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        case .appleScript(.iTerm):
            let script = """
                tell application "iTerm"
                    activate
                    create window with default profile command \(Self.appleScriptQuote(wrappedLine))
                end tell
                """
            return (URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        case .openWithArguments(let prefix):
            return (
                URL(fileURLWithPath: "/usr/bin/open"),
                ["-n", "-b", bundleIdentifier, "--args"] + prefix + shellWrapped
            )
        case .focusOnly:
            return nil
        }
    }

    /// 按 tty 精确选中承载 codex 的 Tab / session（Terminal.app、iTerm2 支持 AppleScript）；
    /// 其他终端返回 nil，退化为只激活 App。
    func focusInvocation(tty: String) -> (executable: URL, arguments: [String])? {
        let quotedTTY = Self.appleScriptQuote(tty)
        switch launch {
        case .appleScript(.terminal):
            let script = """
                tell application "Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is \(quotedTTY) then
                                set selected tab of w to t
                                set index of w to 1
                                activate
                                return "focused"
                            end if
                        end repeat
                    end repeat
                end tell
                return "missing"
                """
            return (URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        case .appleScript(.iTerm):
            let script = """
                tell application "iTerm"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is \(quotedTTY) then
                                    select w
                                    select t
                                    select s
                                    activate
                                    return "focused"
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                return "missing"
                """
            return (URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        case .openWithArguments, .focusOnly:
            return nil
        }
    }

    static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:@%+"))
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuote(_ value: String) -> String {
        "\""
            + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}

struct TerminalInstallation: Equatable, Sendable {
    let app: TerminalApp
    let isRunning: Bool
}

enum TerminalCatalog {
    static let known: [TerminalApp] = [
        TerminalApp(
            bundleIdentifier: "com.apple.Terminal",
            displayName: "Terminal",
            launch: .appleScript(.terminal)
        ),
        TerminalApp(
            bundleIdentifier: "com.googlecode.iterm2",
            displayName: "iTerm2",
            launch: .appleScript(.iTerm)
        ),
        TerminalApp(
            bundleIdentifier: "com.mitchellh.ghostty",
            displayName: "Ghostty",
            launch: .openWithArguments(["-e"])
        ),
        TerminalApp(
            bundleIdentifier: "com.github.wez.wezterm",
            displayName: "WezTerm",
            launch: .openWithArguments(["start", "--"])
        ),
        TerminalApp(
            bundleIdentifier: "org.alacritty",
            displayName: "Alacritty",
            launch: .openWithArguments(["-e"])
        ),
        TerminalApp(
            bundleIdentifier: "net.kovidgoyal.kitty",
            displayName: "kitty",
            launch: .openWithArguments([])
        ),
        TerminalApp(
            bundleIdentifier: "dev.warp.Warp-Stable",
            displayName: "Warp",
            launch: .focusOnly
        ),
        TerminalApp(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "Visual Studio Code",
            launch: .focusOnly
        ),
        TerminalApp(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            displayName: "Cursor",
            launch: .focusOnly
        ),
    ]

    /// 有些终端不直接 fork shell，而是经一个常驻守护进程（父进程是 launchd），
    /// 父进程链走不到 GUI App；按守护进程名映射回终端 bundle id。
    static let helperProcessHosts: [(commandPrefix: String, bundleIdentifier: String)] = [
        ("iTermServer", "com.googlecode.iterm2")
    ]

    static func hostBundleIdentifier(forHelperCommand command: String) -> String? {
        let name = URL(fileURLWithPath: command).lastPathComponent
        return helperProcessHosts.first { name.hasPrefix($0.commandPrefix) }?.bundleIdentifier
    }

    static let tmuxCandidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/opt/local/bin/tmux",
    ]

    static func app(for bundleIdentifier: String, localizedName: String? = nil) -> TerminalApp {
        if let known = known.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return known
        }
        return TerminalApp(
            bundleIdentifier: bundleIdentifier,
            displayName: localizedName ?? bundleIdentifier,
            launch: .focusOnly
        )
    }

    static func installed(
        isInstalled: (String) -> Bool = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        },
        isRunning: (String) -> Bool = {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
    ) -> [TerminalInstallation] {
        known.compactMap { app in
            guard isInstalled(app.bundleIdentifier) else { return nil }
            return TerminalInstallation(app: app, isRunning: isRunning(app.bundleIdentifier))
        }
    }

    static func tmuxExecutable(fileManager: FileManager = .default) -> URL? {
        tmuxCandidates.first { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func hasTmux(fileManager: FileManager = .default) -> Bool {
        tmuxExecutable(fileManager: fileManager) != nil
    }
}
