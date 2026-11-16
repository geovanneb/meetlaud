import Foundation

public extension L10n {
    enum Calendars {
        public static var title: String { text("calendars.title") }
        public static var use: String { text("calendars.use") }
        public static var useNote: String { text("calendars.use_note") }
        public static var denied: String { text("calendars.denied") }
        public static var openSettings: String { text("calendars.open_settings") }
        public static var revoke: String { text("calendars.revoke") }
        public static var none: String { text("calendars.none") }
        public static var addTitle: String { text("calendars.add_title") }
        public static var addHelp: String { text("calendars.add_help") }
    }
}

/// Home's Upcoming, when calendars are not connected.
public extension L10n.Home {
    static var hideConnect: String { L10n.text("home.hide_connect") }
    static var calendarsOffTitle: String { L10n.text("home.calendars_off_title") }
    static var calendarsOffMessage: String { L10n.text("home.calendars_off_message") }
}
