import CoreText
import SwiftUI
import UIKit

/// Renders a single Japanese word with furigana using UIKit attributed string bridged to SwiftUI.
struct FuriganaWordView: UIViewRepresentable {
    let expression: String
    let reading: String
    var fontSize: CGFloat = 36

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = FuriganaRenderer.attributedString(
            expression: expression,
            reading: reading,
            fontSize: fontSize
        )
    }
}

/// Renders a Japanese sentence with per-token furigana over each kanji word.
/// Uses the same morphological analyzer (`JapaneseAnalysisService`) as the
/// chip/sentence views, then attaches a `CTRubyAnnotation` to the range of
/// every kanji-containing token in the line.
struct FuriganaSentenceView: UIViewRepresentable {
    let sentence: String
    var fontSize: CGFloat = 22
    var textAlignment: NSTextAlignment = .center

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = textAlignment
        label.lineBreakMode = .byWordWrapping
        // Allow horizontal compression so the label honours its parent's
        // proposed width and word-wraps the attributed string instead of
        // laying it all out in a single overflowing line.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.textAlignment = textAlignment
        label.attributedText = FuriganaRenderer.attributedSentence(sentence, fontSize: fontSize)
    }

    /// SwiftUI calls this with the proposed container width. Setting
    /// `preferredMaxLayoutWidth` is the documented way to make a UILabel
    /// wrap to a known width, and returning the resulting fitting size
    /// lets SwiftUI lay out the surrounding stack with the correct height.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let fitting = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitting.height)
    }
}

enum FuriganaRenderer {
    static func attributedSentence(_ sentence: String, fontSize: CGFloat) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label
        ]

        // Use a paragraph style with a tall line height so the ruby annotation
        // (~45% of font size) doesn't get clipped by the surrounding lines.
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = fontSize * 1.7
        para.maximumLineHeight = fontSize * 1.9
        para.lineBreakMode = .byWordWrapping

        let segments = JapaneseAnalysisService.shared.segments(sentence)
        let result = NSMutableAttributedString()

        for token in segments {
            let surface = token.surface
            var attrs = baseAttrs
            attrs[.paragraphStyle] = para
            let segment = NSMutableAttributedString(string: surface, attributes: attrs)

            if token.hasKanji && !token.reading.isEmpty && token.reading != surface {
                let rubyAttributes: [CFString: Any] = [
                    kCTRubyAnnotationSizeFactorAttributeName: 0.45,
                    kCTForegroundColorAttributeName: UIColor.secondaryLabel
                ]
                let ruby = CTRubyAnnotationCreateWithAttributes(
                    .auto, .auto, .before,
                    token.reading as CFString,
                    rubyAttributes as CFDictionary
                )
                segment.addAttribute(
                    kCTRubyAnnotationAttributeName as NSAttributedString.Key,
                    value: ruby,
                    range: NSRange(location: 0, length: (surface as NSString).length)
                )
            }
            result.append(segment)
        }

        return result
    }

    static func attributedString(expression: String, reading: String, fontSize: CGFloat) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let color = UIColor.label

        guard !reading.isEmpty, reading != "…", reading != expression else {
            return NSAttributedString(string: expression, attributes: [
                .font: font,
                .foregroundColor: color
            ])
        }

        let rubyAttributes: [CFString: Any] = [
            kCTRubyAnnotationSizeFactorAttributeName: 0.45,
            kCTForegroundColorAttributeName: UIColor.secondaryLabel
        ]

        let ruby = CTRubyAnnotationCreateWithAttributes(
            .auto, .auto, .before,
            reading as CFString,
            rubyAttributes as CFDictionary
        )

        return NSAttributedString(
            string: expression,
            attributes: [
                .font: font,
                .foregroundColor: color,
                kCTRubyAnnotationAttributeName as NSAttributedString.Key: ruby
            ]
        )
    }
}
