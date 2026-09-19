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

    func testRemovesDuplicateTitleAfterLeadingBlankLines() {
        assertBody("\n\n第一章 开始\n正文", title: "第一章 开始", excludesLeadingTitle: true)
    }

    func testKeepsDifferentLeadingTitle() {
        assertBody("第二章 开始\n正文", title: "第一章 开始", excludesLeadingTitle: false)
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
