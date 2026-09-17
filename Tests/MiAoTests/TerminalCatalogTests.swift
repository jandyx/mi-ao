// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

@Test func terminalChoiceRoundTripsThroughRawValue() {
    #expect(CodexCLITerminalChoice(rawValue: "auto") == .auto)
    #expect(CodexCLITerminalChoice(rawValue: "tmux") == .tmux)
    #expect(CodexCLITerminalChoice(rawValue: "app:com.apple.Terminal") == .app("com.apple.Terminal"))
    #expect(CodexCLITerminalChoice(rawValue: "app:") == nil)
    #expect(CodexCLITerminalChoice(rawValue: "iterm") == nil)
    for choice in [CodexCLITerminalChoice.auto, .tmux, .app("x.y")] {
        #expect(CodexCLITerminalChoice(rawValue: choice.rawValue) == choice)
    }
    #expect(CodexCLITerminalChoice.app("com.googlecode.iterm2").displayName == "iTerm2")
    #expect(CodexCLITerminalChoice.app("com.example.unknown").displayName == "com.example.unknown")
}

@Test func terminalCatalogListsInstalledAppsWithRunningState() {
    let installed = TerminalCatalog.installed(
        isInstalled: { ["com.apple.Terminal", "dev.warp.Warp-Stable"].contains($0) },
        isRunning: { $0 == "dev.warp.Warp-Stable" }
    )
    #expect(installed.map(\.app.displayName) == ["Terminal", "Warp"])
    #expect(installed.map(\.isRunning) == [false, true])
    #expect(TerminalCatalog.app(for: "com.example.term", localizedName: "Example").launch == .focusOnly)
    #expect(TerminalCatalog.app(for: "com.example.term", localizedName: "Example").displayName == "Example")
}

@Test func terminalLaunchInvocationsRunThroughLoginShell() {
    // 所有终端都经 `$SHELL -lic`：iTerm2 / open --args 不搜 PATH，而且用户 alias 只在交互 shell 里。
    let terminal = TerminalCatalog.app(for: "com.apple.Terminal")
    let invocation = terminal.launchInvocation(commandLine: "cxd --model x", shell: "/bin/zsh")
    #expect(invocation?.executable.path == "/usr/bin/osascript")
    #expect(invocation?.arguments.last?.contains("do script \"/bin/zsh -lic 'cxd --model x'\"") == true)

    let iterm = TerminalCatalog.app(for: "com.googlecode.iterm2")
    #expect(
        iterm.launchInvocation(commandLine: "codex", shell: "/opt/homebrew/bin/fish")?.arguments.last?.contains(
            "create window with default profile command \"/opt/homebrew/bin/fish -lic codex\""
        ) == true
    )

    let wezterm = TerminalCatalog.app(for: "com.github.wez.wezterm")
    #expect(
        wezterm.launchInvocation(commandLine: "codex", shell: "/bin/bash")?.arguments == [
            "-n", "-b", "com.github.wez.wezterm", "--args", "start", "--", "/bin/bash", "-lic", "codex",
        ]
    )

    #expect(
        TerminalCatalog.app(for: "dev.warp.Warp-Stable").launchInvocation(commandLine: "codex", shell: "/bin/zsh")
            == nil
    )
    #expect(TerminalApp.shellQuote("it's") == "'it'\\''s'")
    #expect(TerminalApp.appleScriptQuote(#"a"b\c"#) == #""a\"b\\c""#)
}

@Test func terminalFocusInvocationsSelectTabByTTY() {
    let iterm = TerminalCatalog.app(for: "com.googlecode.iterm2").focusInvocation(tty: "/dev/ttys001")
    #expect(iterm?.executable.path == "/usr/bin/osascript")
    #expect(iterm?.arguments.last?.contains("if tty of s is \"/dev/ttys001\"") == true)
    #expect(iterm?.arguments.last?.contains("select s") == true)

    let terminal = TerminalCatalog.app(for: "com.apple.Terminal").focusInvocation(tty: "/dev/ttys002")
    #expect(terminal?.arguments.last?.contains("if tty of t is \"/dev/ttys002\"") == true)
    #expect(terminal?.arguments.last?.contains("set selected tab of w to t") == true)

    #expect(TerminalCatalog.app(for: "dev.warp.Warp-Stable").focusInvocation(tty: "/dev/ttys003") == nil)
    #expect(TerminalCatalog.app(for: "com.mitchellh.ghostty").focusInvocation(tty: "/dev/ttys003") == nil)
}

@Test func codexButtonActionsRenameUnderCLITarget() {
    #expect(ButtonAction.codexPreviousTask.displayName(target: .codexCLI) == "Codex CLI · 上一个 Tab")
    #expect(ButtonAction.codexNextTask.displayName(target: .codexCLI) == "Codex CLI · 下一个 Tab")
    #expect(ButtonAction.codexFocus.displayName(target: .codexCLI) == "聚焦 Codex CLI")
    #expect(ButtonAction.codexLaunchOrFocus.displayName(target: .codexCLI) == "启动或聚焦 Codex CLI")
    #expect(ButtonAction.codexPreviousTask.displayName(target: .codexApp) == ButtonAction.codexPreviousTask.displayName)
    #expect(ButtonAction.keyboardReturn.displayName(target: .codexCLI) == ButtonAction.keyboardReturn.displayName)

    #expect(
        MiAoCommandActivity.codexTask(.previous, succeeded: true, target: .codexCLI).presentation.label
            == "Codex CLI · 上一个 Tab")
    #expect(
        MiAoCommandActivity.codexTask(.next, succeeded: false, target: .codexCLI).presentation.label
            == "Codex CLI Tab 切换失败")
    #expect(MiAoCommandActivity.codexTask(.next, succeeded: true).presentation.label == "Codex · 下一个会话")
    #expect(MiAoCommandActivity.codexFocus(succeeded: false, target: .codexCLI).presentation.label == "未找到 Codex CLI")
    #expect(
        MiAoCommandActivity.codexActivation(.cliLaunchRequested(terminal: "iTerm2"), target: .codexCLI).presentation
            .label == "正在 iTerm2 启动 Codex CLI")
    #expect(
        MiAoCommandActivity.codexActivation(.cliNotFound(hint: "x"), target: .codexCLI).presentation.label
            == "未找到 Codex CLI")
}
