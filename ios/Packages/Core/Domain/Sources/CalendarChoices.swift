import Foundation

/// One calendar on the device, such as "Work" in an Exchange account.
public struct CalendarSource: Identifiable, Hashable, Sendable {
    public struct Tint: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public let id: String
    public let title: String
    /// The account that holds it, as iOS names it: "iCloud", "On My iPhone", an Exchange address.
    public let account: String
    /// Two accounts can share a name, so calendars are grouped by this.
    public let accountID: String
    public let tint: Tint?

    public init(id: String, title: String, account: String, accountID: String? = nil, tint: Tint? = nil) {
        self.id = id
        self.title = title
        self.account = account
        self.accountID = accountID ?? account
        self.tint = tint
    }
}

/// Which calendars the person wants the app to use. Kept on the device.
///
/// It stores the calendars that are off, so that a calendar added later in iOS shows up without a visit to Settings.
/// iOS can give a calendar a new identifier after a full sync of its account, and then it shows up again.
public struct CalendarChoices: Sendable {
    static let isOffKey = "calendars.isOff"
    static let hiddenKey = "calendars.hidden"
    static let connectHiddenKey = "calendars.connectHidden"

    /// A name, not the store itself: `UserDefaults` is not `Sendable`, and opening it by name is cheap.
    private let suiteName: String?

    /// `suiteName` nil is the app's standard defaults. Tests and UI tests pass their own.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// The one switch: with it off, the app reads no calendar at all.
    public var isOn: Bool {
        get { !defaults.bool(forKey: Self.isOffKey) }
        nonmutating set { defaults.set(!newValue, forKey: Self.isOffKey) }
    }

    /// The person closed Home's Connect card, or turned calendars off in Settings. Home then shows one quiet line
    /// that leads to Settings, instead of asking again.
    public var isConnectHidden: Bool {
        get { defaults.bool(forKey: Self.connectHiddenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.connectHiddenKey) }
    }

    public var hidden: Set<String> {
        Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    public func isShown(_ id: String) -> Bool {
        !hidden.contains(id)
    }

    public func setShown(_ isShown: Bool, for id: String) {
        var hidden = hidden
        if isShown {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
        defaults.set(hidden.sorted(), forKey: Self.hiddenKey)
    }
}

/// The device's calendars, narrowed to what the person chose. Everything that shows events reads through this.
public struct ChosenCalendars: CalendarProvider {
    private let base: any CalendarProvider
    private let choices: CalendarChoices

    public init(base: any CalendarProvider, choices: CalendarChoices = CalendarChoices()) {
        self.base = base
        self.choices = choices
    }

    /// Turned off in the app reads as not connected, so Home offers Connect again.
    public var access: CalendarAccess {
        choices.isOn ? base.access : .undetermined
    }

    public func requestAccess() async -> Bool {
        choices.isOn = true
        return await base.requestAccess()
    }

    public func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard choices.isOn else { return [] }
        let hidden = choices.hidden
        return await base.events(from: start, to: end).filter { !hidden.contains($0.calendarID) }
    }

    public func calendars() async -> [CalendarSource] {
        await base.calendars()
    }
}
