import SwiftUI

/// Dark-navy hexagonal "A" logo rendered entirely with SwiftUI shapes.
/// No external image asset is required.
struct HexLogoView: View {

    var size: CGFloat = 80

    var body: some View {
        ZStack {
            HexagonShape()
                .fill(Color("NavyBlue"))
                .frame(width: size, height: size)

            Text("A")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - HexagonShape

/// A regular flat-top hexagon drawn as a `Shape` so it scales cleanly.
private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2.0

        // Six vertices of a flat-top hexagon (first point at top-right).
        for i in 0..<6 {
            let angleDeg = Double(60 * i) - 30.0
            let angleRad = angleDeg * .pi / 180.0
            let x = cx + r * CGFloat(cos(angleRad))
            let y = cy + r * CGFloat(sin(angleRad))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    HexLogoView()
        .padding()
}
