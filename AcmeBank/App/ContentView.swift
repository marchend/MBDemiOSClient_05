import SwiftUI

/// Root view of the AcmeBank app.
///
/// Presents `LoginView` as the initial screen.
/// The `onSignIn` closure is a no-op stub \u2014 a future `LoginCoordinator` will
/// replace it with real navigation to the post-auth tab bar.
///
/// This replaces the bootstrap placeholder (`Text("AcmeBank")`).
struct ContentView: View {

    var body: some View {
        LoginView(viewModel: LoginViewModel())
    }
}

#Preview {
    ContentView()
}
