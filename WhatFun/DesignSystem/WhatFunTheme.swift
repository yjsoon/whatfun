import SwiftUI
import UIKit

enum WhatFunTheme {
    static let coral = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.48, blue: 0.36, alpha: 1)
                : UIColor(red: 0.94, green: 0.36, blue: 0.30, alpha: 1)
        }
    )

    static let background = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.09, green: 0.07, blue: 0.10, alpha: 1)
                : UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1)
        }
    )

    static let raisedBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.11, blue: 0.15, alpha: 1)
                : UIColor(red: 1.00, green: 0.98, blue: 0.93, alpha: 1)
        }
    )

    static let ink = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.95, green: 0.91, blue: 0.88, alpha: 1)
                : UIColor(red: 0.18, green: 0.12, blue: 0.18, alpha: 1)
        }
    )

    static let secondaryInk = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.70, green: 0.65, blue: 0.68, alpha: 1)
                : UIColor(red: 0.40, green: 0.34, blue: 0.37, alpha: 1)
        }
    )

    static let sage = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.46, green: 0.63, blue: 0.52, alpha: 1)
                : UIColor(red: 0.37, green: 0.55, blue: 0.43, alpha: 1)
        }
    )

    static let sky = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.46, green: 0.65, blue: 0.78, alpha: 1)
                : UIColor(red: 0.34, green: 0.57, blue: 0.70, alpha: 1)
        }
    )
}

struct ArchiveBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(WhatFunTheme.ink)
            .background(WhatFunTheme.background.ignoresSafeArea())
            .tint(WhatFunTheme.coral)
    }
}

extension View {
    func archiveBackground() -> some View {
        modifier(ArchiveBackground())
    }
}

struct CoverShape: InsettableShape {
    var cornerRadius = 22.0
    var insetAmount = 0.0

    func path(in rect: CGRect) -> Path {
        Path(
            roundedRect: rect.insetBy(dx: insetAmount, dy: insetAmount),
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
    }

    func inset(by amount: CGFloat) -> CoverShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

struct SectionHeading: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
