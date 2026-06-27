import SwiftUI

/// Root view of the AcmeBank app.
///
/// Presents `LoginView` as the initial screen.
/// The `onSignIn` closure is a no-op stub — a future `LoginCoordinator` will
/// replace it with real navigation to the post-auth tab bar.
///
/// `LoginViewModel` is owned here as a `@StateObject` so that SwiftUI anchors
/// its lifetime to `ContentView`, not to any per-body-evaluation call site.
/// This follows the coordinator-owned injection model from `bootstrap.md §3`.
struct ContentView: View {

    @StateObject private var loginViewModel = LoginViewModel()

    var body: some View {
        LoginView(viewModel: loginViewModel)
    }
}

#Preview {
    ContentView()
}
