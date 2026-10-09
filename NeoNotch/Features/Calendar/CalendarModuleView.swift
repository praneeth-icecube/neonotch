import SwiftUI

/// The calendar widget: month, the day's events with their calendar's
/// colour down the side, and yesterday / today / tomorrow along the bottom.
struct CalendarModuleView: View {
    @ObservedObject var calendar: CalendarModel
    /// Shows the ✦ button for an Apple Intelligence brief of the day.
    var canBrief: Bool
    var onBrief: () -> Void

    private static let visibleEvents = 2

    var body: some View {
        Group {
            switch calendar.access {
            case .granted: schedule
            case .notDetermined, .denied: permission
            }
        }
        .onAppear { calendar.reload() }
    }

    // MARK: Schedule

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            events
            Spacer(minLength: 4)
            dayStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(calendar.selectedDay.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.primary)
            Spacer(minLength: 0)
            if canBrief {
                headerButton("sparkles", help: "Brief me on this day", action: onBrief)
            }
            headerButton("plus", help: "Open Calendar") { calendar.openCalendar() }
        }
        .padding(.bottom, 6)
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(NotchTheme.secondary)
        .help(help)
    }

    @ViewBuilder
    private var events: some View {
        if calendar.events.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.isShowingToday ? "No events today" : "No events")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.secondary)
                Text("Enjoy the free time")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(calendar.events.prefix(Self.visibleEvents)) { event in
                    EventRow(event: event)
                        .onTapGesture { calendar.open(event) }
                        .help(event.location.map { "\(event.title) — \($0)" } ?? event.title)
                }
                let hidden = calendar.events.count - Self.visibleEvents
                if hidden > 0 {
                    Button("+\(hidden) more") { calendar.openCalendar() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NotchTheme.tertiary)
                }
            }
        }
    }

    private var dayStrip: some View {
        HStack(spacing: 3) {
            ForEach(calendar.days, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { calendar.select(day) }
                } label: {
                    VStack(spacing: 1) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NotchTheme.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NotchTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? NotchTheme.fillHover : .clear)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.94))
            }
        }
    }

    // MARK: Permission

    private var permission: some View {
        let denied = calendar.access == .denied
        return VStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(NotchTheme.secondary)
            Text(denied ? "Calendar is off" : "Your schedule")
                .font(.system(size: 12, weight: .semibold))
            Text(denied ? "Allow NeoNotch in Privacy & Security" : "Today's events, one hover away")
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(denied ? "Open Settings" : "Allow") { calendar.requestAccess() }
                .buttonStyle(NotchPillButtonStyle(prominent: true, compact: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventRow: View {
    let event: CalendarEvent

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.25)
                .fill(Color(nsColor: event.color))
                .frame(width: 2.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.primary)
                    .lineLimit(1)
                Text(event.timeRange)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(event.isOver ? 0.5 : 1)
        .brightness(isHovering ? 0.08 : 0)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}
