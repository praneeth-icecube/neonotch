import CoreGraphics

/// A widget on the Home tab.
///
/// `width` is the content width. Every module adds `padding` on either side
/// and a hairline between neighbours, so the Home row is exactly as wide as
/// the widgets you have switched on — see `rowWidth`.
enum HomeModule: String, CaseIterable, Identifiable {
    case music
    case timer
    case calendar
    case bookmarks
    /// Your Apple Reminders. Stored as "notes": it began as quick notes, and
    /// saved layouts still say so.
    case reminders = "notes"
    /// A new note straight into Apple Notes.
    case notes = "appleNotes"
    case focus
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "Music"
        case .timer: "Timer"
        case .calendar: "Calendar"
        case .bookmarks: "Bookmarks"
        case .reminders: "Reminders"
        case .notes: "Notes"
        case .focus: "Focus"
        case .mirror: "Mirror"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .timer: "timer"
        case .calendar: "calendar"
        case .bookmarks: "bookmark"
        case .reminders: "checklist"
        case .notes: "note.text"
        case .focus: "brain.head.profile"
        case .mirror: "web.camera"
        }
    }

    /// How wide this widget sits in the Home row.
    var width: CGFloat {
        switch self {
        case .music: 262
        case .timer: 156
        case .calendar: 156
        case .bookmarks: 72
        case .reminders: 146
        case .notes: 140
        case .focus: 124
        case .mirror: 112
        }
    }

    /// What Home shows out of the box. Calendar is there to switch on in
    /// Settings; Timer took its place.
    static let standard: [HomeModule] = [.music, .timer, .bookmarks, .reminders, .notes, .focus, .mirror]

    static let padding: CGFloat = 12

    /// Width of a row of modules, padding and dividers included.
    static func rowWidth(_ modules: [HomeModule]) -> CGFloat {
        guard !modules.isEmpty else { return 0 }
        return modules.reduce(0) { $0 + $1.width + padding * 2 } + CGFloat(modules.count - 1)
    }

    /// Where a module starts within the row, for anchoring overlays over it.
    static func offset(of module: HomeModule, in modules: [HomeModule]) -> CGFloat? {
        guard let index = modules.firstIndex(of: module) else { return nil }
        return modules[..<index].reduce(0) { $0 + $1.width + padding * 2 + 1 }
    }
}
