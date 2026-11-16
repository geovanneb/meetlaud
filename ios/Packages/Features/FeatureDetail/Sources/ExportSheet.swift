import DesignSystem
import Domain
import Localization
import SwiftUI
import UIKit

enum ExportChoice: Hashable {
    case audio
    case transcript(TranscriptFormat)
    case summaryMarkdown
    case summaryPDF
}

/// Picks what to share. The file exists only while this sheet is open.
struct ExportSheet: View {
    let model: DetailModel
    @State private var choice = ExportChoice.transcript(.txt)
    @State private var options = ExportOptions()
    @State private var file: URL?
    @State private var failed = false
    @State private var folder = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)")
    @Environment(\.dismiss) private var dismiss

    private var choices: [(ExportChoice, String)] {
        var result: [(ExportChoice, String)] = []
        if !model.segments.isEmpty {
            result += TranscriptFormat.allCases.map { format in
                (.transcript(format), "\(L10n.Transcript.title) (\(format.rawValue.uppercased()))")
            }
        }
        if model.selectedSummary != nil {
            result.append((.summaryMarkdown, "\(L10n.Summary.title) (MD)"))
            result.append((.summaryPDF, "\(L10n.Summary.title) (PDF)"))
        }
        if model.hasAudio {
            result.append((.audio, "\(L10n.Detail.audio) (M4A)"))
        }
        return result
    }

    private var showsOptions: Bool {
        if case let .transcript(format) = choice {
            format.usesOptions
        } else {
            false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.Detail.exportWhat, selection: $choice) {
                        ForEach(choices, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("export.choice")
                } header: {
                    // The system draws an inline picker's own label too faintly for the contrast audit.
                    SectionHeader(L10n.Detail.exportWhat)
                }
                if showsOptions {
                    Section {
                        Toggle(L10n.Detail.exportSpeakers, isOn: $options.includesSpeakers)
                        Toggle(L10n.Detail.exportTimestamps, isOn: $options.includesTimestamps)
                    }
                }
            }
            .screenScrollMargins()
            // Outside the form, so that the one action on this page never scrolls away.
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let file {
                        ShareLink(item: file) {
                            Label(L10n.Detail.exportShare, systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryAction()
                        .accessibilityIdentifier("export.share")
                    } else if failed {
                        VStack(spacing: Spacing.small) {
                            Text(L10n.Detail.exportFailed)
                                .font(.dsMeta)
                                .foregroundStyle(Color.dsSecondaryText)
                                .multilineTextAlignment(.center)
                            Button(L10n.Detail.exportRetry) { Task { await prepare() } }
                                .primaryAction()
                        }
                        .accessibilityIdentifier("export.failure")
                    } else {
                        ProgressView()
                            .frame(minHeight: 44)
                    }
                }
                .padding(Spacing.medium)
            }
            .navigationTitle(L10n.Detail.export)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done) { dismiss() }
                }
            }
        }
        .task {
            if let first = choices.first, !choices.contains(where: { $0.0 == choice }) {
                choice = first.0
            }
        }
        .task(id: [AnyHashable(choice), AnyHashable(options)]) { await prepare() }
        .onDisappear { try? FileManager.default.removeItem(at: folder) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.export")
    }

    private func prepare() async {
        file = nil
        try? FileManager.default.removeItem(at: folder)
        failed = false
        let title = model.recording?.title ?? ""
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            switch choice {
            case .audio:
                let target = target(title, "m4a")
                try FileManager.default.copyItem(at: model.audioFile, to: target)
                file = target
            case let .transcript(format):
                file = try write(model.exportedTranscript(format: format, options: options), title, format.rawValue)
            case .summaryMarkdown:
                file = try write(model.exportedSummary(), title, "md")
            case .summaryPDF:
                let target = target(title, "pdf")
                try SummaryPDF.render(markdown: model.exportedSummary()).write(to: target)
                file = target
            }
        } catch {
            file = nil
            failed = true
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func target(_ title: String, _ fileExtension: String) -> URL {
        folder.appending(path: ExportFileName.safe(title, fileExtension: fileExtension))
    }

    private func write(_ text: String, _ title: String, _ fileExtension: String) throws -> URL {
        let url = target(title, fileExtension)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Lays text out on A4 pages. The system text stack handles Japanese and page breaks.
enum SummaryPDF {
    static func render(markdown: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let formatter = UISimpleTextPrintFormatter(attributedText: attributed(markdown))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 48, dy: 48), forKey: "printableRect")
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            for index in 0 ..< renderer.numberOfPages {
                context.beginPage()
                renderer.drawPage(at: index, in: context.pdfContextBounds)
            }
        }
    }

    private static func attributed(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in markdown.components(separatedBy: "\n") {
            let (text, font): (String, UIFont) = if line.hasPrefix("## ") {
                (String(line.dropFirst(3)), .boldSystemFont(ofSize: 15))
            } else if line.hasPrefix("# ") {
                (String(line.dropFirst(2)), .boldSystemFont(ofSize: 20))
            } else {
                (line, .systemFont(ofSize: 12))
            }
            result.append(NSAttributedString(string: text + "\n", attributes: [.font: font]))
        }
        return result
    }
}
