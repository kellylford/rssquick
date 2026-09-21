import AppKit
import Testing
@testable import RSSQuickUI

@Suite("Colour and text size", .serialized)
@MainActor
struct ThemeTests {
    /// No literal colours anywhere.
    ///
    /// Everything the window draws takes its colour from a system catalog colour, so Dark Mode,
    /// Increase Contrast and Reduce Transparency all work without this code hearing about them.
    /// A fixed grey for the date line would be near-invisible under Increase Contrast, which is
    /// exactly the setting the reader who needs that line most will have turned on.
    @Test("Everything the window draws takes its colour from the system")
    func noLiteralColours() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.folder)
        harness.table.layoutSubtreeIfNeeded()

        let literals = ThemeTests.literalColours(in: harness.window.contentView!)

        #expect(literals.isEmpty, "these are not system colours: \(literals.joined(separator: ", "))")
    }

    /// Colour conveys nothing to a screen reader or to a colour-blind reader, and a dark blue
    /// folder name is unreadable against the background of a high contrast theme.
    @Test("Folders are marked out by weight, never by colour")
    func foldersDifferByWeightAlone() async throws {
        let harness = try await FocusHarness.make()
        harness.outline.layoutSubtreeIfNeeded()

        let folderRow = harness.outline.row(forItem: harness.folder)
        let feedRow = harness.outline.row(forItem: harness.goodFeed)

        let folderCell = try #require(harness.outline.view(atColumn: 0, row: folderRow, makeIfNecessary: true) as? FeedCellView)
        let feedCell = try #require(harness.outline.view(atColumn: 0, row: feedRow, makeIfNecessary: true) as? FeedCellView)

        let folderFont = try #require(folderCell.textField?.font)
        let feedFont = try #require(feedCell.textField?.font)

        let folderTraits = NSFontManager.shared.traits(of: folderFont)
        let feedTraits = NSFontManager.shared.traits(of: feedFont)

        #expect(folderTraits.contains(.boldFontMask))
        #expect(!feedTraits.contains(.boldFontMask))
        #expect(folderCell.textField?.textColor == feedCell.textField?.textColor)
    }

    @Test("Text size follows the reader's setting, not a fixed number")
    func textSizeIsApplied() async throws {
        let harness = try await FocusHarness.make()
        let original = TextScale.current
        defer { TextScale.current = original }

        TextScale.current = 1.0
        harness.controller.applyTextScale()
        let normal = try #require(harness.controller.statusField.font?.pointSize)
        let normalRowHeight = harness.outline.rowHeight

        TextScale.current = 2.0
        harness.controller.applyTextScale()
        let doubled = try #require(harness.controller.statusField.font?.pointSize)

        #expect(doubled > normal * 1.9)
        #expect(harness.outline.rowHeight > normalRowHeight, "rows still fit one line of the larger text")
    }

    @Test("A larger text size reaches the headlines too, not just the chrome")
    func textSizeReachesTheRows() async throws {
        let harness = try await FocusHarness.make()
        let original = TextScale.current
        defer { TextScale.current = original; harness.controller.applyTextScale() }

        await harness.pressReturnOnFeed(harness.goodFeed)

        TextScale.current = 1.0
        harness.controller.applyTextScale()
        let normalCell = try #require(harness.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? HeadlineCellView)
        let normal = try #require(normalCell.textField?.font?.pointSize)

        TextScale.current = 2.0
        harness.controller.applyTextScale()
        let largeCell = try #require(harness.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? HeadlineCellView)
        let large = try #require(largeCell.textField?.font?.pointSize)

        #expect(large > normal * 1.9)
    }

    /// A colour that came from `NSColor.labelColor` and friends is a catalog colour. One built
    /// from components is a literal, whoever wrote it.
    private static func literalColours(in view: NSView) -> [String] {
        var found: [String] = []

        if let field = view as? NSTextField, let colour = field.textColor, colour.type != .catalog {
            found.append("\(type(of: view)) text \"\(field.stringValue.prefix(24))\": \(colour)")
        }

        if let box = view as? NSBox, box.boxType == .custom, box.fillColor.type != .catalog {
            found.append("NSBox fill: \(box.fillColor)")
        }

        if let table = view as? NSTableView, table.backgroundColor.type != .catalog {
            found.append("\(type(of: view)) background: \(table.backgroundColor)")
        }

        for subview in view.subviews { found += literalColours(in: subview) }
        return found
    }
}

@Suite("The remembered text size")
@MainActor
struct TextScaleTests {
    @Test("Anything outside the supported range reads as ordinary text")
    func clamping() {
        #expect(TextScale.clamp(0.1) == TextScale.minimum)
        #expect(TextScale.clamp(99) == TextScale.maximum)
        #expect(TextScale.clamp(.nan) == 1.0)
        #expect(TextScale.clamp(1.5) == 1.5)
    }

    @Test("Larger and smaller step through the sizes and stop at the ends")
    func stepping() {
        let original = TextScale.current
        defer { TextScale.current = original }

        TextScale.reset()
        #expect(TextScale.current == 1.0)

        TextScale.larger()
        #expect(TextScale.current > 1.0)

        TextScale.smaller()
        #expect(TextScale.current == 1.0)

        TextScale.smaller()
        #expect(TextScale.current == TextScale.minimum, "smaller than ordinary text is not offered")

        for _ in 0..<20 { TextScale.larger() }
        #expect(TextScale.current == TextScale.maximum)
    }
}
