// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation

enum MiAoRuntimeNotifications {
    static let buttonConfigurationChanged = Notification.Name(
        "com.poemcoder.mi-ao.button-configuration-changed"
    )
    static let buttonActivity = Notification.Name("com.poemcoder.mi-ao.button-activity")
    static let voiceConnectionModeChanged = Notification.Name(
        "com.poemcoder.mi-ao.voice-connection-mode-changed"
    )
    static let codexTargetChanged = Notification.Name(
        "com.poemcoder.mi-ao.codex-target-changed"
    )
    static let voiceRetryRequested = Notification.Name(
        "com.poemcoder.mi-ao.voice-retry-requested"
    )

    static func postButtonConfigurationChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            buttonConfigurationChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postButtonActivity(button: RemoteButton, isPressed: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            buttonActivity,
            object: nil,
            userInfo: ["button": button.rawValue, "phase": isPressed ? "down" : "up"],
            deliverImmediately: true
        )
    }

    static func postVoiceRetryRequested() {
        DistributedNotificationCenter.default().postNotificationName(
            voiceRetryRequested,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postCodexTargetChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            codexTargetChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postVoiceConnectionModeChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            voiceConnectionModeChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
