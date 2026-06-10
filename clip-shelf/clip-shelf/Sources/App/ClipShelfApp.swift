//
//  ClipShelfApp.swift
//  clip-shelf
//
//  Created by DIO on 2026/03/28.
//

import AppKit
import SwiftUI

@main
struct ClipShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            if let dependencies = appDelegate.dependencies {
                SettingsView(dependencies: dependencies)
            } else {
                EmptyView()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published fileprivate private(set) var dependencies: AppDependencies?
    private var menuBarController: MenuBarController?
    private var pastePickerWindow: PastePickerWindow?
    private var historyWindow: HistoryWindow?
    private var settingsWindow: SettingsWindow?
    private var appearanceController: AppearanceController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let dependencies = try AppDependencies()
            self.dependencies = dependencies

            let historyWindow = HistoryWindow(dependencies: dependencies)
            let pastePickerWindow = PastePickerWindow(
                dependencies: dependencies,
                showHistory: { historyWindow.show() }
            )
            let settingsWindow = SettingsWindow(dependencies: dependencies)
            self.pastePickerWindow = pastePickerWindow
            self.historyWindow = historyWindow
            self.settingsWindow = settingsWindow
            self.appearanceController = AppearanceController(settingsStore: dependencies.settings)

            menuBarController = MenuBarController(
                dependencies: dependencies,
                showPicker: { pastePickerWindow.show() },
                showHistory: { historyWindow.show() },
                showSettings: { settingsWindow.show() }
            )

            dependencies.hotkey.onPickerHotkey = { pastePickerWindow.show() }
            dependencies.hotkey.onHistoryHotkey = { historyWindow.show() }
            dependencies.hotkey.registerAll()
            dependencies.monitor.start()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "clip-shelf could not start"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dependencies?.monitor.stop()
        dependencies?.hotkey.unregisterAll()
    }
}
