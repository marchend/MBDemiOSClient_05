import SwiftUI

/// Bootstrap placeholder. Future PRs will replace this with RootView
/// which switches between the Login flow and the TabBar based on auth state.
struct ContentView: View {
    var body: some View {
        Text("AcmeBank")
            .font(.largeTitle)
            .fontWeight(.bold)
            .multilineTextAlignment(.center)
            .padding()
    }
}

#Preview {
    ContentView()
}
