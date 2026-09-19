import XCTest
@testable import Legado

final class BookReaderDocumentBuilderTests: XCTestCase {
    func testRemovesExactDuplicateLeadingTitle() {
        assertBody("第一章 开始\n正文", title: "第一章 开始", excludesLeadingTitle: true)
    }

    func testRemovesDuplicateTitleWithWhitespaceDifferences() {
        assertBody("  第一章   开始  \n正文", title: "第一章 开始", excludesLeadingTitle: true)
    }

    func testRemovesDuplicateTitleWithFullWidthSpaces() {
        assertBody("第一章　开始\n正文", title: "第一章 开始", excludesLeadingTitle: true)
    }

    func testRemovesDuplicateTitleWithNBSP() {
        assertBody("第一章\u{00A0}开始\n正文", title: "第一章 开始", excludesLeadingTitle: true)
    }

    func testRemovesDuplicateTitleAfterLeadingBlankLines() {
        assertBody("\n\n第一章 开始\n正文", title: "第一章 开始", excludesLeadingTitle: true)
    }

    func testKeepsDifferentLeadingTitle() {
        assertBody("第二章 开始\n正文", title: "第一章 开始", excludesLeadingTitle: false)
    }

    func testKeepsTitleAndPromotesItWhenNoSynthesizedTitleExists() {
        let document = makeDocument(content: "第一章 开始\n正文", title: "")
        XCTAssertEqual(document.paragraphs.first { !$0.isBlank }?.kind, .chapterTitle)
        XCTAssertTrue(document.paragraphs.contains { $0.attributed.string == "第一章 开始" })
    }

    func testPreservesSourceRangeAndParagraphIndexAfterDeduplication() {
        let document = BookReaderDocumentBuilder.make(title: "第一章 开始", text: "\n第一章 开始\n正文", markers: [], reviewsEnabled: true, font: .systemFont(ofSize: 18), markerColor: .secondaryLabel)
        let body = document.paragraphs.first { $0.attributed.string.hasPrefix("正文") }
        XCTAssertEqual(body?.sourceRange.location, 8)
        let link = body?.attributed.attribute(.link, at: max((body?.attributed.length ?? 1) - 1, 0), effectiveRange: nil) as? URL
        XCTAssertEqual(link.flatMap(BookReaderLink.resolve), .paragraph(2))
    }

    func testContinuousTextUsesDeduplicatedDocument() {
        let document = makeDocument(content: "第一章 开始\n正文", title: "第一章 开始")
        let text = document.continuousText(font: .systemFont(ofSize: 18), lineSpacing: 4, paragraphSpacing: 8, indent: 20, titleSpacing: 12).string
        XCTAssertEqual(text.components(separatedBy: "第一章 开始").count - 1, 1)
    }

    func testKeepsMatchingTitleInMiddleOfBody() {
        let document = makeDocument(content: "正文开头\n第一章 开始\n正文结尾", title: "第一章 开始")
        XCTAssertTrue(document.paragraphs.contains { $0.attributed.string == "第一章 开始" })
    }

    private func assertBody(_ content: String, title: String, excludesLeadingTitle: Bool) {
        let document = makeDocument(content: content, title: title)
        let bodyStrings = document.paragraphs.dropFirst().map { $0.attributed.string }
        XCTAssertEqual(bodyStrings.contains { BookReaderDocumentBuilder.isDuplicateChapterTitle($0, title: title) }, !excludesLeadingTitle)
    }

    private func makeDocument(content: String, title: String) -> BookReaderDocument {
        BookReaderDocumentBuilder.make(
            title: title,
            text: content,
            markers: [],
            reviewsEnabled: false,
            font: .systemFont(ofSize: 18),
            markerColor: .secondaryLabel
        )
    }
}
