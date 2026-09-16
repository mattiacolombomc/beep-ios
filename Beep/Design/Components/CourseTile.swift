import SwiftUI

/// Small colored square with the course monogram. Content layer, no glass.
struct CourseTile: View {
    let monogram: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Text(monogram)
            .font(.system(size: monogram.count > 3 ? 11 : 13, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.white)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}
