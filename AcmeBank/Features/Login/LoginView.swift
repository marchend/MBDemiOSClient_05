import SwiftUI

/// Main login screen.
///
/// Composed from subcomponents defined in `Features/Login/Components/`.
/// Takes a `LoginViewModel` as a `@StateObject` so the view owns the lifecycle.
///
/// **Tint / placeholder colour note:** Do NOT apply `.tint`, `.accentColor`, or
/// `.foregroundColor` to the `TextField` / `SecureField` wrappers. Doing so
/// colours the placeholder text which should remain in the system default faded grey.
struct LoginView: View {

    @StateObject var viewModel: LoginViewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Header strip ──────────────────────────────────────────────
            OktaHeaderView()

            // ── Scrollable body ───────────────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    // Logo + title
                    HexLogoView(size: 80)

                    Text("Acme Bank")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.top, 16)

                    Text("Sign in to your account")
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.bottom, 32)

                    // ── Username field ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("name@acmebank.com", text: $viewModel.username)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .accessibilityIdentifier("usernameField")
                    }
                    .padding(.bottom, 16)

                    // ── Password field ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ZStack(alignment: .trailing) {
                            if viewModel.isPasswordVisible {
                                TextField("Password", text: $viewModel.password)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(.horizontal, 12)
                                    .padding(.trailing, 44)
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("passwordField")
                            } else {
                                SecureField("Password", text: $viewModel.password)
                                    .padding(.horizontal, 12)
                                    .padding(.trailing, 44)
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("passwordField")
                            }

                            Button(action: { viewModel.isPasswordVisible.toggle() }) {
                                Image(systemName: viewModel.isPasswordVisible
                                      ? "eye.slash"
                                      : "eye")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityIdentifier("togglePasswordVisibility")
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }
                    .padding(.bottom, 16)

                    // ── Error banner ───────────────────────────────────────
                    ErrorBannerView(message: viewModel.errorMessage)
                        .padding(.bottom, viewModel.errorMessage != nil ? 16 : 0)

                    // ── Keep me signed in ──────────────────────────────────
                    HStack {
                        Button(action: { viewModel.keepSignedIn.toggle() }) {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.keepSignedIn
                                      ? "checkmark.square.fill"
                                      : "square")
                                    // Spec: Dark navy is used ONLY for the hex 'A' logo
                                    // and the full-width 'Sign in' button. Use monochrome
                                    // styles for all other elements.
                                    .foregroundStyle(viewModel.keepSignedIn
                                                     ? .primary
                                                     : .secondary)

                                Text("Keep me signed in")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("keepSignedInToggle")

                        Spacer()
                    }
                    .padding(.bottom, 24)

                    // ── Sign In button ─────────────────────────────────────
                    Button(action: { viewModel.signIn() }) {
                        Text("Sign in")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(viewModel.isSignInEnabled
                                  ? Color("NavyBlue")
                                  : Color(.systemGray4))
                    )
                    .disabled(!viewModel.isSignInEnabled)
                    .padding(.bottom, 32)
                    .accessibilityIdentifier("signInButton")

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }

            // ── Footer ────────────────────────────────────────────────────
            SecuredByOktaView()
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Previews

#Preview("Default — fields empty") {
    LoginView(viewModel: LoginViewModel())
}

#Preview("Error banner visible") {
    let vm = LoginViewModel()
    vm.errorMessage = "Incorrect username or password. Please try again."
    vm.username = "user@acmebank.com"
    return LoginView(viewModel: vm)
}

#Preview("Button enabled") {
    let vm = LoginViewModel()
    vm.username = "user@acmebank.com"
    vm.password = "secret"
    return LoginView(viewModel: vm)
}
