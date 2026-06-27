import SwiftUI
import UIKit

/// Static decorative header strip shown at the top of the login screen.
///
/// Displays "acmebank.okta.com" and an Okta logo.
/// Falls back to `Image(systemName: "circle.fill")` when the `okta_logo`
/// image asset is absent from the asset catalog.
struct OktaHeaderView: View {

    /// `true` when `okta_logo` is present in the asset catalog.
    private var hasOktaLogo: Bool {
        UIImage(named: "okta_logo") != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)

            Text("acmebank.okta.com")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            // `okta_logo` is expected in Assets.xcassets.
            // If absent, a plain circle acts as a visual placeholder
            // so the build never fails on a missing asset.
            if hasOktaLogo {
                Image("okta_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }
}

#Preview {
    OktaHeaderView()
}
