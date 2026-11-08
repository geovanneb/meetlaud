import Foundation

/// The parts of a Markdown document that a phone should lay out itself. `AttributedString` handles what is inside a
/// line, such as links and bold, but it leaves tables and headings as raw text.
public enum MarkdownBlock: Equatable, Sendable {
    case title(String)
    case heading(String)
    case paragraph(String)
    case bullet(String)
    case table(rows: [[String]])

    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var rows: [[String]] = []

        func closeTable() {
            if !rows.isEmpty {
                // The first row names the columns, which the layout does not need.
                blocks.append(.table(rows: Array(rows.dropFirst())))
                rows = []
            }
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") {
                let cells = cells(in: trimmed)
                if !isDivider(cells) {
                    rows.append(cells)
                }
                continue
            }
            closeTable()
            if trimmed.hasPrefix("## ") {
                blocks.append(.heading(String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.title(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
            } else if !trimmed.isEmpty {
                blocks.append(.paragraph(trimmed))
            }
        }
        closeTable()
        return blocks
    }

    private static func cells(in line: String) -> [String] {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isDivider(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { "-:".contains($0) } }
    }
}

public extension String {
    /// Links and emphasis, styled. Falls back to the plain text, so a bad line still reads.
    var inlineMarkdown: AttributedString {
        (try? AttributedString(markdown: self)) ?? AttributedString(self)
    }
}
