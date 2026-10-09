import SwiftUI

/// The battery capsule for the panel header: a drawn battery filled to
/// the real level, then the percentage. Green on power, red at 20% and under.
struct BatteryCapsule: View {
    @ObservedObject var battery: BatteryModel

    var body: some View {
        if let level = battery.level {
            HStack(spacing: 5) {
                BatteryGlyph(level: level, isCharging: battery.isCharging || battery.isPluggedIn)
                Text("\(level)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.secondary)
            }
            .help(battery.isCharging ? "Charging" : (battery.isPluggedIn ? "On power" : "On battery"))
        }
    }
}

struct BatteryGlyph: View {
    let level: Int
    let isCharging: Bool

    private static let bodySize = CGSize(width: 24, height: 12)

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                    .fill(fill)
                    .frame(width: max(2, (Self.bodySize.width - 4) * CGFloat(level) / 100), height: Self.bodySize.height - 4)
                    .padding(.leading, 2)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7.5, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: Self.bodySize.width, height: Self.bodySize.height)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.45))
                .frame(width: 1.5, height: 4)
        }
    }

    private var fill: Color {
        if isCharging { return NotchViewModel.chargingGreen }
        if level <= 20 { return Color(red: 1, green: 0.3, blue: 0.3) }
        return Color.white.opacity(0.85)
    }
}
