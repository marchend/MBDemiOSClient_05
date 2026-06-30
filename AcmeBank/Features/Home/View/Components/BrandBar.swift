import SwiftUI

/// Top-of-screen brand bar for the Home dashboard.
///
/// Renders the navy hex "A" logo tile alongside the "Acme Bank"
/// wordmark. Stateless — owns no model, takes no inputs.
///
/// The hex logo is drawn as a small rounded-rect tile containing a
/// bold "A". A real asset catalog entry is intentionally not pulled
/// in: keeping the brand mark as SwiftUI primitives means previews
/// and snapshots render with no missing-asset warnings on a fresh
/// checkout, and the monochrome navy palette is enforced in code.
public struct BrandBar: View {

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AcmeColors.navy900)
                    .frame(width: 32, height: 32)
                Text("A")
                    .font(.system(size: 18, weight: .heavy, design: .default))
                    .foregroundStyle(AcmeColors.onNavy)
                    .accessibilityHidden(true)
            }
            Text("Acme Bank")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AcmeColors.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Acme Bank")
        .accessibilityIdentifier("home.brandBar")
    }
}

#Preview {
    BrandBar()
        .padding()
        .background(AcmeColors.background)
}
