import SwiftUI
import UIKit
import BookCardCore

@main struct BookCardMobileApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            MobileSessionView().environmentObject(store)
        }
    }
}

struct MobileSessionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showKey = false

    var body: some View {
        Group {
            if !store.hasKey && store.cache.books.isEmpty {
                MobileKeyView(initial: true, onConnected: {})
            } else if UIDevice.current.userInterfaceIdiom == .pad {
                iPadLibraryView(showKey: $showKey)
            } else {
                iPhoneLibraryView(showKey: $showKey)
            }
        }
        .sheet(isPresented: $showKey) {
            MobileKeyView(initial: false, onConnected: { showKey = false })
                .interactiveDismissDisabled(store.busy)
        }
    }
}
