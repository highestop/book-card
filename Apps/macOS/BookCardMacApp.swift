import SwiftUI
import AppKit
import BookCardCore

@main struct BookCardApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .frame(minWidth: 850, minHeight: 580)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1080, height: 740)
    }
}
