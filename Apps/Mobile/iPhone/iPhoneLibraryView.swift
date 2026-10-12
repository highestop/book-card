import SwiftUI
import BookCardCore

struct iPhoneLibraryView: View {
    @Binding var showKey: Bool
    var body: some View {
        TabView {
            NavigationStack { MobileHomeView().mobileControls(showKey: $showKey) }
                .tabItem { Label("最近书签", systemImage: "rectangle.stack") }
            NavigationStack { MobileShelfView().mobileControls(showKey: $showKey) }
                .tabItem { Label("全部书签", systemImage: "books.vertical") }
        }
    }
}
