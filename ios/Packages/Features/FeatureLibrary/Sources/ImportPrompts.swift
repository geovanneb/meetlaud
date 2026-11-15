import Localization
import SwiftUI
import UniformTypeIdentifiers

/// The file picker and its errors, attached once at the root of the app.
public struct ImportPrompts: ViewModifier {
    @Bindable private var library: LibraryController

    public init(library: LibraryController) {
        self.library = library
    }

    public func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $library.showsFilePicker,
                allowedContentTypes: [.audio, .movie],
                allowsMultipleSelection: true,
            ) { result in
                if case let .success(urls) = result {
                    library.importFiles(urls)
                }
            }
            .alert(L10n.Library.importFailed, isPresented: $library.showsImportFailure) {
                Button(L10n.Common.ok, role: .cancel) {}
            } message: {
                Text(L10n.Library.importFailedMessage)
            }
    }
}
