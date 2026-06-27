import SwiftUI

/// Inline error banner used by the Login screen for auth failures.
///
/// Accepts an optional `String` message:
/// - When `message` is `nil` the view collapses to zero height so it takes no space.
/// - When `message` is non-nil it renders a rounded rectangle with a light red
///   tinted background and an `exclamationmark.triangle.fill` warning glyph, per
///   MBE2EDEM05-9 AC #7 (auth-error banner styling).
///
/// Styling per AC #7:
/// - background: `Color(.systemRed).opacity(0.1)`
/// - icon: `exclamationmark.triangle.fill` tinted `.red`
/// - text colour: `.primary` (so it remains legible in both colour schemes)
struct ErrorBannerView: View {

    let message: String?

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("errorBannerIcon")

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("errorBannerText")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemRed).opacity(0.1))
            )
            .accessibilityIdentifier("errorBanner")
        }
    }
}

#Preview("With message") {
    ErrorBannerView(message: "Incorrect username or password.")
        .padding()
}

#Preview("No message \u{2014} zero height") {
    VStack {
        Text("Above banner")
        ErrorBannerView(message: nil)
        Text("Below banner")
    }
    .padding()
}
