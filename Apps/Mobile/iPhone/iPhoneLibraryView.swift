import SwiftUI

struct iPhoneLibraryView: View {
    @Binding var showKey: Bool
    var body: some View {
        NavigationStack {
            MobileHomeView()
                .toolbar(.hidden, for: .navigationBar)
        }.mobileControls(showKey: $showKey)
    }
}
