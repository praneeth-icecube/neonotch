import SwiftUI

/// Small games that fit in a notch: a runner, and two that end in
/// under a minute.
struct PlayView: View {
    @ObservedObject var viewModel: NotchViewModel
    @State private var game: Game = .runner

    enum Game: String, CaseIterable, Identifiable {
        case runner, reaction, memory
        var id: String { rawValue }
        var title: String {
            switch self {
            case .runner: "Runner"
            case .reaction: "Reaction"
            case .memory: "Memory"
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                ForEach(Game.allCases) { option in
                    Button {
                        withAnimation(.notchSpring) { game = option }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(game == option ? 0.16 : 0.06))
                            )
                            .foregroundStyle(.white.opacity(game == option ? 0.95 : 0.55))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 72)

            NotchDivider()
                .padding(.vertical, 4)

            PanelCard {
                switch game {
                case .runner:
                    // A round in progress holds the panel open and keeps the
                    // keyboard, the same way typing a note does.
                    RunnerGameView { active in viewModel.setTextEntry(active) }
                case .reaction: ReactionGameView()
                case .memory: MemoryGameView()
                }
            }
        }
    }
}

// MARK: - Reaction

private final class ReactionGame: ObservableObject {
    enum Phase: Equatable {
        case idle, waiting, go, result(Int), tooSoon
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var best: Int = UserDefaults.standard.integer(forKey: "reactionBest")

    private var goDate: Date?
    private var generation = 0

    func tap() {
        switch phase {
        case .idle, .result, .tooSoon:
            arm()
        case .waiting:
            generation &+= 1
            phase = .tooSoon
        case .go:
            guard let goDate else { return }
            let milliseconds = Int(Date().timeIntervalSince(goDate) * 1000)
            phase = .result(milliseconds)
            if best == 0 || milliseconds < best {
                best = milliseconds
                UserDefaults.standard.set(milliseconds, forKey: "reactionBest")
            }
        }
    }

    private func arm() {
        generation &+= 1
        let token = generation
        phase = .waiting
        let delay = Double.random(in: 1.2...4.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token else { return }
            self.goDate = Date()
            self.phase = .go
        }
    }
}

private struct ReactionGameView: View {
    @StateObject private var game = ReactionGame()

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(background)
                Text(caption)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(captionColor)
                    .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
            .onTapGesture { game.tap() }
            .animation(.easeOut(duration: 0.12), value: game.phase)

            Text(game.best > 0 ? "Best \(game.best) ms" : "Click to start")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(10)
    }

    private var background: Color {
        switch game.phase {
        case .idle: .white.opacity(0.14)
        case .waiting: .red.opacity(0.8)
        case .go: .green.opacity(0.85)
        case .result: .white.opacity(0.85)
        case .tooSoon: .orange.opacity(0.85)
        }
    }

    /// The idle pad is dark, every other phase is a bright colour.
    private var captionColor: Color {
        game.phase == .idle ? .white.opacity(0.8) : .black.opacity(0.75)
    }

    private var caption: String {
        switch game.phase {
        case .idle: "Click to begin"
        case .waiting: "Wait for green…"
        case .go: "Click!"
        case .result(let milliseconds): "\(milliseconds) ms — again?"
        case .tooSoon: "Too soon — again?"
        }
    }
}

// MARK: - Memory

private final class MemoryGame: ObservableObject {
    @Published private(set) var sequence: [Int] = []
    @Published private(set) var highlighted: Int?
    @Published private(set) var isShowing = false
    @Published private(set) var round = 0
    @Published private(set) var best = UserDefaults.standard.integer(forKey: "memoryBest")
    @Published private(set) var failed = false

    private var inputIndex = 0
    private var generation = 0

    func startOrRestart() {
        generation &+= 1
        sequence = []
        round = 0
        failed = false
        nextRound()
    }

    func tap(_ pad: Int) {
        guard !isShowing, !sequence.isEmpty, !failed else { return }
        flash(pad)
        guard sequence[inputIndex] == pad else {
            failed = true
            if round - 1 > best {
                best = round - 1
                UserDefaults.standard.set(best, forKey: "memoryBest")
            }
            return
        }
        inputIndex += 1
        if inputIndex == sequence.count {
            if round > best {
                best = round
                UserDefaults.standard.set(best, forKey: "memoryBest")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.nextRound()
            }
        }
    }

    private func nextRound() {
        inputIndex = 0
        round += 1
        sequence.append(Int.random(in: 0..<4))
        replay()
    }

    private func replay() {
        generation &+= 1
        let token = generation
        isShowing = true
        for (offset, pad) in sequence.enumerated() {
            let start = 0.35 + Double(offset) * 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + start) { [weak self] in
                guard let self, self.generation == token else { return }
                self.highlighted = pad
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + start + 0.35) { [weak self] in
                guard let self, self.generation == token else { return }
                self.highlighted = nil
                if offset == self.sequence.count - 1 { self.isShowing = false }
            }
        }
    }

    private func flash(_ pad: Int) {
        highlighted = pad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            if self?.highlighted == pad { self?.highlighted = nil }
        }
    }
}

private struct MemoryGameView: View {
    @StateObject private var game = MemoryGame()

    private static let colors: [Color] = [.green, .red, .yellow, .blue]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { pad in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Self.colors[pad].opacity(game.highlighted == pad ? 1 : 0.3))
                        .frame(width: 30)
                        .contentShape(Rectangle())
                        .onTapGesture { game.tap(pad) }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 12)
            .animation(.easeOut(duration: 0.1), value: game.highlighted)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.failed ? "Missed it" : "Round \(max(game.round, 1))")
                    .font(.system(size: 13, weight: .semibold))
                Text(game.best > 0 ? "Best round \(game.best)" : "Watch, then repeat")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
                Button(game.sequence.isEmpty ? "Start" : "Restart") {
                    game.startOrRestart()
                }
                .buttonStyle(ShelfActionStyle())
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }
}
