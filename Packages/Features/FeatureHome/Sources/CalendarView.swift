import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

/// A week that opens into a month, with the chosen day's meetings below it.
public struct CalendarScreen: View {
    private let model: HomeModel
    private let onRecordEvent: (CalendarEvent) -> Void
    @Environment(AppRouter.self) private var router
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var isExpanded = false

    private static let monthsAround = 18
    private let calendar = Calendar.current

    public init(model: HomeModel, onRecordEvent: @escaping (CalendarEvent) -> Void) {
        self.model = model
        self.onRecordEvent = onRecordEvent
    }

    private var days: [Date] {
        isExpanded
            ? CalendarGrid.month(containing: selected, calendar: calendar)
            : CalendarGrid.week(containing: selected, calendar: calendar)
    }

    private var visibleMonth: Date {
        CalendarGrid.startOfMonth(containing: selected, calendar: calendar)
    }

    public var body: some View {
        VStack(spacing: 0) {
            CalendarDaysGrid(
                days: days,
                selected: selected,
                month: visibleMonth,
                isExpanded: isExpanded,
                hasContent: { model.hasContent(on: $0) },
                onSelect: { selected = $0 },
            )
            .gesture(swipe)
            if isExpanded {
                CalendarMonthStrip(
                    months: CalendarGrid.months(
                        around: .now, before: Self.monthsAround, after: Self.monthsAround, calendar: calendar,
                    ),
                    selected: visibleMonth,
                    onSelect: choose(month:),
                )
                .riseTransition()
            }
            Divider()
            agenda
        }
        .motion(Motion.standard, value: isExpanded)
        .motion(Motion.quick, value: selected)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            PromptBar(placeholder: L10n.Home.askPlaceholder) { router.open(.ask(recording: nil)) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task(id: visibleMonth) { await model.loadCalendar(month: visibleMonth) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.calendar")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: Spacing.xSmall) {
                    Text(selected.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.dsHeading)
                    Image(systemName: "chevron.down")
                        .font(.dsBadge)
                        .rotationEffect(isExpanded ? .degrees(180) : .zero)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.dsPrimaryText)
                .fixedSize()
            }
            .accessibilityValue(isExpanded ? L10n.Home.calendarExpanded : L10n.Home.calendarCollapsed)
            .accessibilityIdentifier("calendar.title")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            Button(L10n.Home.today) { selected = calendar.startOfDay(for: .now) }
                .accessibilityIdentifier("calendar.today")
        }
    }

    /// Sideways moves by what is on screen: a month when open, a week when closed.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            let step = value.translation.width < 0 ? 1 : -1
            let moved = isExpanded
                ? calendar.date(byAdding: .month, value: step, to: selected)
                : calendar.date(byAdding: .weekOfYear, value: step, to: selected)
            selected = moved ?? selected
        }
    }

    /// Today, in the month it is in. Otherwise the month's first day.
    private func choose(month: Date) {
        let today = calendar.startOfDay(for: .now)
        selected = calendar.isDate(today, equalTo: month, toGranularity: .month) ? today : month
    }

    /// Meetings and recordings together, in the order the day went.
    private var agendaItems: [AgendaItem] {
        let events = model.events(on: selected).map { AgendaItem.event($0) }
        let recordings = model.recordings(on: selected).map { AgendaItem.recording($0) }
        return (events + recordings).sorted { $0.start < $1.start }
    }

    @ViewBuilder private var agenda: some View {
        let items = agendaItems
        if items.isEmpty {
            emptyDay
        } else {
            List {
                Section {
                    ForEach(items, content: row)
                        .listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            .screenList()
            .contentMargins(.top, 0, for: .scrollContent)
            // No bar sits over this list, so the fade made for one would only dim its first row.
            .scrollEdgeEffectHidden(true, for: .top)
        }
    }

    @ViewBuilder private func row(_ item: AgendaItem) -> some View {
        switch item {
        case let .event(event):
            EventRow(event: event, showsDay: false, canRecord: event.end > .now) { onRecordEvent(event) }
        case let .recording(recording):
            Button {
                router.push(.recording(recording.id, at: nil))
            } label: {
                RecordingRow(recording: recording, showsDay: false)
            }
            .buttonStyle(.plain)
            .disabled(recording.status != .ready)
        }
    }

    @ViewBuilder private var emptyDay: some View {
        switch model.calendarAccess {
        case .granted:
            EmptyState(title: L10n.Home.dayEmpty, message: L10n.Home.noEventsMessage, symbol: "calendar")
        case .undetermined:
            VStack(spacing: Spacing.medium) {
                EmptyState(title: L10n.Home.dayEmpty, message: L10n.Home.connectMessage, symbol: "calendar")
                    .frame(maxHeight: 220)
                Button(L10n.Home.connect) {
                    Task {
                        await model.connectCalendar()
                        await model.loadCalendar(month: visibleMonth)
                    }
                }
                .primaryAction()
                .accessibilityIdentifier("calendar.connect")
                Spacer(minLength: 0)
            }
        case .denied:
            EmptyState(title: L10n.Home.dayEmpty, message: L10n.Home.calendarDenied, symbol: "calendar")
        }
    }
}

private enum AgendaItem: Identifiable {
    case event(CalendarEvent)
    case recording(Recording)

    var id: String {
        switch self {
        case let .event(event): "event-\(event.id)"
        case let .recording(recording): "recording-\(recording.id.rawValue)"
        }
    }

    var start: Date {
        switch self {
        case let .event(event): event.start
        case let .recording(recording): recording.createdAt
        }
    }
}

/// The weekday letters and the days under them. Custom because the system's date picker has no week view, and it
/// could not share this animation. Each day is a real button, so VoiceOver and Dynamic Type work as usual.
private struct CalendarDaysGrid: View {
    let days: [Date]
    let selected: Date
    let month: Date
    let isExpanded: Bool
    let hasContent: (Date) -> Bool
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: CalendarGrid.daysInWeek)
    @ScaledMetric private var dayCircle: CGFloat = 36

    var body: some View {
        VStack(spacing: Spacing.xSmall) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(
                    Array(CalendarGrid.weekdayLetters(calendar: calendar).enumerated()),
                    id: \.offset,
                ) { _, letter in
                    Text(letter)
                        .font(.dsNote)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
            // Each day already says its full date, so VoiceOver has no use for a row of letters.
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(days, id: \.self, content: day)
            }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.small)
        .clipped()
    }

    private func day(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let inMonth = !isExpanded || calendar.isDate(date, equalTo: month, toGranularity: .month)
        return Button {
            onSelect(calendar.startOfDay(for: date))
        } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.day()))
                    .font(.dsRowTitle)
                    .foregroundStyle(color(isSelected: isSelected, inMonth: inMonth))
                    .frame(width: dayCircle, height: dayCircle)
                    .background(isSelected ? Color.dsPrimaryText : .clear, in: .circle)
                Circle()
                    .fill(hasContent(date) ? Color.dsAction : .clear)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day")
    }

    private func color(isSelected: Bool, inMonth: Bool) -> Color {
        if isSelected {
            return .dsBackground
        }
        return inMonth ? .dsPrimaryText : .dsSecondaryText
    }
}

/// A row of months to jump between, with the year where it changes.
private struct CalendarMonthStrip: View {
    let months: [Date]
    let selected: Date
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.small) {
                    ForEach(months, id: \.self) { month in
                        if calendar.component(.month, from: month) == 1 {
                            Text(month.formatted(.dateTime.year()))
                                .font(.dsHeading)
                                .foregroundStyle(Color.dsPrimaryText)
                        }
                        chip(month)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, month in
                withAnimation(Motion.standard) { proxy.scrollTo(month, anchor: .center) }
            }
        }
    }

    private func chip(_ month: Date) -> some View {
        let isSelected = calendar.isDate(month, equalTo: selected, toGranularity: .month)
        return Button {
            onSelect(month)
        } label: {
            Text(month.formatted(.dateTime.month(.abbreviated)))
                .font(.dsMeta)
                .foregroundStyle(isSelected ? Color.dsBackground : Color.dsPrimaryText)
                .padding(.horizontal, Spacing.medium)
                .frame(minHeight: 44)
                .background {
                    Capsule().fill(isSelected ? Color.dsPrimaryText : Color.dsSurface)
                    Capsule().strokeBorder(Color.dsSelection)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .id(month)
        .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar.month")
    }
}
