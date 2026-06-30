import SwiftUI

/// Footer "Log out" control on the Home dashboard.
///
/// Stateless: takes an `onSignOut` closure and invokes it on tap. The
/// real sign-out side effects (clearing the Keychain, flipping the
/// coordinator route back to `.login`) live in the ViewModel /
/// `SessionStore` — see the Home story's "Log out / 401 contract" in
/// `CLAUDE.md`. Keeping the button dumb means the same control can
/// also be wired up from previews, tests, and any future "force
/// sign-out" admin flow without touching its implementation.
public struct LogOutButton: View {

    public let onSignOut: () -> Void

    public init(onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
    }

    public var body: some View {
        Button(action: onSignOut) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Log out")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AcmeColors.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AcmeColors.divider, lineWidth: 1)
            )
        }
        .accessibilityIdentifier("home.logOut")
        .accessibilityLabel("Log out")
    }
}

#Preview {
    LogOutButton(onSignOut: {})
        .padding()
        .background(AcmeColors.background)
}
