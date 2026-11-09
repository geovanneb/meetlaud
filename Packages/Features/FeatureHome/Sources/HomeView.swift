import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

public struct HomeView: View {
    private let model: HomeModel
    private let onRecord: () -> Void
    private let onRecordEvent: (CalendarEvent) -> Void
    private let onImport: () -> Void
    private let center: TranscriptionCenter
    @Environment(AppRouter.self) private var router
    @AppStorage(RecordingSort.storageKey) private var sort: RecordingSort = .newest

    public init(
        model: HomeModel,
        center: TranscriptionCenter,
        onRecord: @escaping () -> Void,
        onRecordEvent: @escaping (CalendarEvent) -> Void,
        onImport: @escaping () -> Void,
    ) {
        self.model = model
        self.center = center
        self.onRecord = onRecord
        self.onRecordEvent = onRecordEvent
        self.onImport = onImport
    }

    public var body: some View {
        List {
            upcoming
            meetingNotes
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenBackground()
        .task { await model.refreshEvents() }
        .toolbar { toolbar }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.home")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: onRecord) {
                // A Label shows only its icon in a toolbar, and this action needs its name.
                HStack(spacing: Spacing.xSmall) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(Color.dsRecord)
                        .accessibilityHidden(true)
                    Text(L10n.Home.record)
                }
                .accessibilityShowsLargeContentViewer()
            }
            .accessibilityIdentifier("home.record")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            Menu(L10n.Home.add, systemImage: "plus") {
                Button(L10n.Home.startRecording, systemImage: "mic", action: onRecord)
                Button(L10n.Home.importFiles, systemImage: "square.and.arrow.down", action: onImport)
                Button(L10n.Home.newChat, systemImage: "plus.bubble") {
                    router.open(.ask(recording: nil))
                }
            }
            .accessibilityIdentifier("home.add")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.dsPageTitle)
            .foregroundStyle(Color.dsPrimaryText)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Upcoming

    private var upcoming: some View {
        Section {
            switch model.calendarAccess {
            case .granted:
                if model.nextEvents.isEmpty {
                    Text(L10n.Home.noEvents)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(model.nextEvents) { event in
                        EventRow(event: event) { onRecordEvent(event) }
                            .listRowBackground(Color.clear)
                    }
                }
            case .undetermined:
                if model.isConnectHidden {
                    calendarsOffRow
                } else {
                    connectCard
                }
            case .denied:
                Text(L10n.Home.calendarDenied)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .listRowBackground(Color.clear)
            }
        } header: {
            HStack {
                sectionHeader(L10n.Home.upcoming)
                Spacer()
                Button {
                    router.push(.calendar)
                } label: {
                    HStack(spacing: Spacing.xSmall) {
                        Text(L10n.Home.calendarView)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .tappableTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.calendar")
            }
        }
        .listSectionSeparator(.hidden)
        .motion(Motion.standard, value: model.isConnectHidden)
    }

    private var connectCard: some View {
        HStack(spacing: Spacing.medium) {
            RowLabel(L10n.Home.connectTitle, detail: L10n.Home.connectMessage)
            Spacer(minLength: 0)
            Button {
                Task { await model.connectCalendar() }
            } label: {
                Text(L10n.Home.connect)
                    .tappableTarget()
            }
            .foregroundStyle(Color.dsAction)
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.connect")
            Button {
                model.hideConnect()
            } label: {
                Image(systemName: "xmark")
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .tappableTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Home.hideConnect)
            .accessibilityIdentifier("home.connect.hide")
        }
        .padding(Spacing.medium)
        .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.medium, bottom: 0, trailing: Spacing.medium))
    }

    /// After the Connect card is closed: one quiet line, and the way back is in Settings.
    private var calendarsOffRow: some View {
        Button {
            router.push(.calendars)
        } label: {
            HStack(spacing: Spacing.medium) {
                RowLabel(L10n.Home.calendarsOffTitle, detail: L10n.Home.calendarsOffMessage)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.dsSecondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("home.calendarsOff")
    }

    // MARK: - Meeting notes

    private var meetingNotes: some View {
        Section {
            // Inside the section, not over the whole list: an overlay lands on top of the
            // upcoming events once a calendar is connected.
            if model.recordings.isEmpty {
                emptyNotes
            }
            ForEach(sort.sorted(model.recordings)) { recording in
                Button {
                    router.push(.recording(recording.id, at: nil))
                } label: {
                    RecordingRow(recording: recording, progress: center.progress[recording.id])
                }
                .buttonStyle(.plain)
                .disabled(recording.status != .ready)
                .listRowBackground(Color.clear)
            }
        } header: {
            HStack {
                sectionHeader(L10n.Home.meetingNotes)
                Spacer()
                Menu {
                    Picker(L10n.Library.sortBy, selection: $sort) {
                        ForEach(RecordingSort.allCases, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                } label: {
                    Label(L10n.Library.sortBy, systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                        .tappableTarget()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsSecondaryText)
            }
        }
        .listSectionSeparator(.hidden)
    }

    private var emptyNotes: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.dsHero)
                .foregroundStyle(Color.dsSecondaryText)
                .padding(.bottom, Spacing.small)
                .accessibilityHidden(true)
            // Two texts, not one combined element: the accessibility audit cannot tell that a combined node follows
            // Dynamic Type, and fails it. VoiceOver reads them one after the other, as in `EmptyState`.
            Text(L10n.Home.emptyTitle)
                .font(.dsSectionTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.empty")
            Text(L10n.Home.emptyMessage)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.large)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

extension Date {
    /// "Today at 15:00", in the person's language.
    var scheduleText: String {
        Self.schedule.string(from: self)
    }

    private static let schedule = relativeFormatter(date: .medium, time: .short)

    private static func relativeFormatter(
        date: DateFormatter.Style,
        time: DateFormatter.Style,
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = date
        formatter.timeStyle = time
        formatter.doesRelativeDateFormatting = true
        return formatter
    }
}

struct EventRow: View {
    let event: CalendarEvent
    /// Off where the day is already on screen, and only the time is news.
    var showsDay = true
    var canRecord = true
    let onRecord: () -> Void

    private var when: String {
        showsDay ? event.start.scheduleText : event.start.formatted(date: .omitted, time: .shortened)
    }

    private var detail: String {
        ([when] +
            (event.attendees.isEmpty ? [] : [event.attendees.prefix(3).joined(separator: ", ")]))
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            RowLabel(
                event.hasTitle ? event.title : L10n.Home.untitledEvent,
                detail: detail,
            )
            Spacer(minLength: 0)
            if canRecord {
                Button(action: onRecord) {
                    Label(L10n.Home.record, systemImage: "record.circle")
                        .labelStyle(.iconOnly)
                        .font(.dsIconLarge)
                        .tappableTarget()
                }
                .foregroundStyle(Color.dsRecord)
                .buttonStyle(.plain)
                .accessibilityIdentifier("event.record")
            }
        }
    }
}
