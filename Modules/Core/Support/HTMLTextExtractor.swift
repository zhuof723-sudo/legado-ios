import Foundation
import SwiftSoup

// MARK: - HTML → plain text (engine side)
//
// Ported from the app's Models.swift: converts HTML to plain text while
// preserving paragraph boundaries. Block-level elements become line breaks;
// inline elements have their tags removed.

extension String {
    /// Converts HTML to plain text while preserving paragraph boundaries.
    var strippedHTML: String {
        do {
            let doc = try SwiftSoup.parse(self)
            try doc.select("script, style, noscript, iframe").remove()
            let root: SwiftSoup.Element = doc.body() ?? doc
            return HTMLTextExtractor.extractPreservingBlocks(root)
        } catch {
            return self
        }
    }
}

/// Recursively traverses the DOM, inserting line breaks at block-level
/// element boundaries.
private enum HTMLTextExtractor {
    static let blockTags: Set<String> = [
        "p", "div", "br", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "tr", "blockquote", "section", "article",
        "dt", "dd", "figcaption", "pre", "header", "footer",
    ]

    static func extractPreservingBlocks(_ element: SwiftSoup.Element) -> String {
        var result = ""
        for node in element.getChildNodes() {
            if let textNode = node as? SwiftSoup.TextNode {
                result += textNode.getWholeText()
            } else if let child = node as? SwiftSoup.Element {
                let tag = child.tagName().lowercased()
                if tag == "br" {
                    result += "\n"
                } else if blockTags.contains(tag) {
                    // Block element: add newlines before and after
                    if !result.isEmpty && !result.hasSuffix("\n") {
                        result += "\n"
                    }
                    result += extractPreservingBlocks(child)
                    if !result.hasSuffix("\n") {
                        result += "\n"
                    }
                } else {
                    // Inline element: extract text directly
                    result += extractPreservingBlocks(child)
                }
            }
        }
        return result
    }
}
