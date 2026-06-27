import SwiftUI

/// Inline error banner used by the Login screen for auth failures.
///
/// Accepts an optional `String` message:
/// - When `message` is `nil` the view collapses to zero height so it takes no space.
/// - When `message` is non-nil it renders a rounded rectangle with a light red
///   tinted background and an `exclamationmark.triangle.fill` warning glyph, per
///   MBE2EDEM05-9 AC #7 (auth-error banner styling).
struct ErrorBannerView: View {

    let message: String?

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(.systemRed))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemRed).opacity(0.1))
            )
        }
    }
}

#Preview("With message") {
    ErrorBannerView(message: "Incorrect username or password.")
        .padding()
}

#Preview("No message — zero height") {
    VStack {
        Text("Above banner")
        ErrorBannerView(message: nil)
        Text("Below banner")
    }
    .padding()
}
