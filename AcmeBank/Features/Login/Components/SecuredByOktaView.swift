import SwiftUI
import UIKit

/// Static footer displayed at the bottom of the login screen.
///
/// Shows "Secured by" followed by the Okta logo.
/// Falls back to `Image(systemName: "circle.fill")` when the `okta_logo`
/// image asset is absent from the asset catalog.
struct SecuredByOktaView: View {

    /// `true` when `okta_logo` is present in the asset catalog.
    private var hasOktaLogo: Bool {
        UIImage(named: "okta_logo") != nil
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("Secured by")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // `okta_logo` is expected in Assets.xcassets.
            // Falls back to a system image if the asset is absent.
            if hasOktaLogo {
                Image("okta_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 16)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            Text("okta")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    SecuredByOktaView()
}
