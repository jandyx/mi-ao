// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation

struct AppRuntimeLaunchPlan: Equatable {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL
    let environment: [String: String]

    static func make(
        context: MiAoInstallationContext,
        preferences: AppPreferences,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntimeLaunchPlan {
        // MI_AO_DEBUG=1 open 米遥.app：让 App 启动的运行时也打印原始 GATT / HID 数据，便于排查。
        let debugArguments = environment["MI_AO_DEBUG"] == "1" ? ["--debug"] : []
        return AppRuntimeLaunchPlan(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [context.startScriptURL.path] + preferences.runtimeArguments + debugArguments,
            currentDirectoryURL: context.startScriptURL.deletingLastPathComponent()
                .deletingLastPathComponent(),
            environment: MiAoProcessEnvironment.sanitizedForExternalProcess(environment)
        )
    }
}

struct AppRuntimeLauncher {
    func start(preferences: AppPreferences) throws -> String {
        guard let context = MiAoInstallationContext.load(), context.isValid else {
            throw BridgeError.configuration("App 内置启动组件缺失或损坏，请打开设置向导修复")
        }

        let plan = AppRuntimeLaunchPlan.make(context: context, preferences: preferences)
        let process = Process()
        let output = Pipe()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        process.currentDirectoryURL = plan.currentDirectoryURL
        process.environment = plan.environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let message =
            String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw BridgeError.configuration(
                message.isEmpty ? "启动脚本退出码：\(process.terminationStatus)" : message
            )
        }
        return message
    }
}
