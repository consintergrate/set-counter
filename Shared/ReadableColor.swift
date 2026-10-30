import SwiftUI
import UIKit

extension Color {
    /// This color dark enough for text on a light background (WCAG 4.5:1 against white).
    /// The bright system greens, oranges, and teals fall well short of that in light mode;
    /// dark mode keeps the color as it is, since it already reads well on black.
    var readable: Color {
        let base = UIColor(self)
        return Color(uiColor: UIColor { traits in
            let color = base.resolvedColor(with: traits)
            guard traits.userInterfaceStyle != .dark else { return color }
            return color.darkened(toContrastWithWhite: 4.5)
        })
    }

    /// A fixed color from a hex value like 0xC2410C.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private extension UIColor {
    /// WCAG relative luminance of the sRGB color.
    var luminance: CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> CGFloat {
            let value = min(max(value, 0), 1)
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Lowers the brightness, keeping the hue, until the color meets `ratio` against white.
    func darkened(toContrastWithWhite ratio: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        var color = self
        while 1.05 / (color.luminance + 0.05) < ratio, brightness > 0.05 {
            brightness -= 0.02
            color = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        }
        return color
    }
}
