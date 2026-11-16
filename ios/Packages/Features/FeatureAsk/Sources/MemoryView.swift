import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

/// What the app keeps in mind in every chat, in plain sight.
public struct MemoryView: View {
    private let controller: AskController
    @State private var isAdding = false
    @State private var editing: MemoryItem?
    @State private var text = ""

    public init(controller: AskController) {
        self.controller = controller
    }

    public var body: some View {
        List {
            if controller.memories.isEmpty {
                EmptyState(title: L10n.Ask.memory, message: L10n.Ask.memoryHint, symbol: "brain", inline: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(controller.memories) { memory in
                Button {
                    text = memory.text
                    editing = memory
                } label: {
                    Text(memory.text)
                        .foregroundStyle(Color.dsPrimaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tappableTarget()
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(L10n.Ask.delete, systemImage: "trash", role: .destructive) {
                        Task { await controller.delete(memory) }
                    }
                }
                .contextMenu {
                    Button(L10n.Ask.delete, systemImage: "trash", role: .destructive) {
                        Task { await controller.delete(memory) }
                    }
                }
                .accessibilityIdentifier("memory.item")
                .listRowBackground(Color.clear)
            }
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Ask.memory)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.Ask.memoryAdd, systemImage: "plus") {
                    text = ""
                    isAdding = true
                }
                .accessibilityIdentifier("memory.add")
            }
        }
        .modifier(NamePrompt(title: L10n.Ask.memoryAdd, isPresented: $isAdding, name: $text) {
            let value = text
            Task { await controller.addMemory(value) }
        })
        .modifier(NamePrompt(
            title: L10n.Ask.memory,
            isPresented: Binding(get: { editing != nil }, set: {
                if !$0 {
                    editing = nil
                }
            }),
            name: $text,
        ) {
            guard let editing else { return }
            let value = text
            Task { await controller.update(editing, text: value) }
        })
        .task { await controller.reload() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.memory")
    }
}
