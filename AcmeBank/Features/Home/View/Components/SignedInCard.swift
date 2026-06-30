import SwiftUI

/// The navy "SIGNED IN" card at the top of the Home dashboard.
///
/// Renders the signed-in customer's full name + phone, an initials
/// avatar, and the monochrome `checkmark.shield` trust footer
/// ("Authenticated via Okta · Customer <id>"). Stateless — all
/// values are passed in by the parent view from the `Customer` value
/// type so previews and tests can drive it with any fixture.
public struct SignedInCard: View {

    public let fullName: String
    public let phoneNumber: String?
    public let customerId: String

    public init(fullName: String, phoneNumber: String?, customerId: String) {
        self.fullName = fullName
        self.phoneNumber = phoneNumber
        self.customerId = customerId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIGNED IN")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(AcmeColors.onNavySubtle)

            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(fullName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AcmeColors.onNavy)
                        .accessibilityIdentifier("home.signedIn.name")
                    if let phoneNumber, !phoneNumber.isEmpty {
                        Text(phoneNumber)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AcmeColors.onNavySubtle)
                            .accessibilityIdentifier("home.signedIn.phone")
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AcmeColors.onNavySubtle)
                    .accessibilityHidden(true)
                // U+00B7 MIDDLE DOT separator. Braced escape used for
                // safety even though the literal · is also valid.
                Text("Authenticated via Okta \u{00B7} Customer \(customerId)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AcmeColors.onNavySubtle)
                    .accessibilityIdentifier("home.signedIn.trust")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AcmeColors.navy900)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.signedInCard")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(AcmeColors.navy800)
            Circle()
                .stroke(AcmeColors.onNavy.opacity(0.25), lineWidth: 1)
            Text(initials(from: fullName))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AcmeColors.onNavy)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    /// Two-letter uppercase initials from the first and last whitespace-
    /// separated tokens. Single-word names return one letter.
    private func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        let letters = [parts.first, parts.count > 1 ? parts.last : nil]
            .compactMap { $0?.first }
            .map { String($0).uppercased() }
        return letters.joined()
    }
}

#Preview {
    SignedInCard(
        fullName: "Bank User",
        phoneNumber: "+1 (555) 010-0101",
        customerId: "C-1001"
    )
    .padding()
    .background(AcmeColors.background)
}
