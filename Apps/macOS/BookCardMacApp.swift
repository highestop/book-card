import SwiftUI
import AppKit
import BookCardCore

#if !PREVIEW_RENDER
@main struct BookCardApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .frame(minWidth: 860, minHeight: 640)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1180, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("同步读书笔记") { Task { await store.refresh() } }
                    .keyboardShortcut("r").disabled(store.busy || !store.hasKey)
            }
        }
    }
}
#endif
