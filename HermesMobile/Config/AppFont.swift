import SwiftUI

enum AppFont {
    static func largeTitle(weight: Font.Weight? = nil) -> Font {
        system(.largeTitle, weight: weight)
    }

    static func body(weight: Font.Weight? = nil) -> Font {
        system(.body, weight: weight)
    }

    static func callout(weight: Font.Weight? = nil) -> Font {
        system(.callout, weight: weight)
    }

    static func subheadline(weight: Font.Weight? = nil) -> Font {
        system(.subheadline, weight: weight)
    }

    static func footnote(weight: Font.Weight? = nil) -> Font {
        system(.footnote, weight: weight)
    }

    static func caption(weight: Font.Weight? = nil) -> Font {
        system(.caption, weight: weight)
    }

    static func caption2(weight: Font.Weight? = nil) -> Font {
        system(.caption2, weight: weight)
    }

    static func headline(weight: Font.Weight? = nil) -> Font {
        system(.headline, weight: weight)
    }

    static func title(weight: Font.Weight? = nil) -> Font {
        system(.title, weight: weight)
    }

    static func title2(weight: Font.Weight? = nil) -> Font {
        system(.title2, weight: weight)
    }

    static func title3(weight: Font.Weight? = nil) -> Font {
        system(.title3, weight: weight)
    }

    static func mono(style: Font.TextStyle = .body, weight: Font.Weight? = nil) -> Font {
        system(style, design: .monospaced, weight: weight)
    }

    /// Warm assistant prose: Dynamic Type-scaled New York via SwiftUI's serif
    /// design, set in italic for the Samantha/Zora voice treatment.
    static func voice(style: Font.TextStyle = .body, weight: Font.Weight? = nil) -> Font {
        system(style, design: .serif, weight: weight).italic()
    }

    /// Extra leading for italic serif prose. Keeps the voice treatment legible
    /// in dense assistant responses without loosening tables or code blocks.
    static let voiceRelativeLineSpacing: CGFloat = 0.22

    static func monoDigit(style: Font.TextStyle = .body, weight: Font.Weight? = nil) -> Font {
        mono(style: style, weight: weight).monospacedDigit()
    }

    private static func system(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        weight: Font.Weight? = nil
    ) -> Font {
        .system(style, design: design, weight: weight)
    }
}
