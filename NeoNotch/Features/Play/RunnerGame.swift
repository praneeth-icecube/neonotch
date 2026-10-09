import AppKit
import SwiftUI

/// The runner: a chicken, cacti, and birds once you are doing well.
/// Space, ↑ or a click to jump; hold ↓ to skid under a bird.
///
/// The world steps inside the canvas's render pass, driven by an animation
/// timeline, so nothing here is published per frame — only the phase, and
/// that change is deferred out of the render pass.
final class RunnerGame: ObservableObject {
    enum Phase { case ready, running, over }

    struct Obstacle {
        enum Kind { case cactus, bird }
        var kind: Kind
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
        /// Height of the bottom edge above the ground.
        var lift: CGFloat
    }

    @Published private(set) var phase: Phase = .ready
    private(set) var best = UserDefaults.standard.integer(forKey: "runnerBest")

    // World, in points. y grows upward from the ground line.
    private(set) var playerLift: CGFloat = 0
    private(set) var isSkidding = false
    private(set) var obstacles: [Obstacle] = []
    private(set) var distance: CGFloat = 0
    private var velocity: CGFloat = 0
    private var speed: CGFloat = RunnerGame.startSpeed
    private var untilNextSpawn: CGFloat = 320
    private var lastTime: TimeInterval?
    var size: CGSize = .zero

    static let playerX: CGFloat = 46
    static let playerSize = CGSize(width: 20, height: 22)
    /// Distance from the ground line to the bottom of the surface.
    static let groundInset: CGFloat = 12
    private static let startSpeed: CGFloat = 200
    private static let maxSpeed: CGFloat = 440
    private static let gravity: CGFloat = 2_500
    private static let jumpVelocity: CGFloat = 690

    var score: Int { Int(distance / 12) }
    var groundY: CGFloat { size.height - Self.groundInset }

    // MARK: Input

    /// Space, ↑ or a click: jump, or start a round.
    func jump() {
        switch phase {
        case .ready, .over:
            start()
        case .running:
            if playerLift <= 0.5 {
                velocity = Self.jumpVelocity
                isSkidding = false
            }
        }
    }

    func setSkid(_ skidding: Bool) {
        guard phase == .running else { return }
        isSkidding = skidding
        // Skidding in mid-air drops you back down faster.
        if skidding, playerLift > 0 { velocity = min(velocity, -Self.jumpVelocity * 0.6) }
    }

    private func start() {
        obstacles = []
        distance = 0
        speed = Self.startSpeed
        playerLift = 0
        velocity = 0
        isSkidding = false
        untilNextSpawn = 260
        lastTime = nil
        phase = .running
    }

    // MARK: Simulation

    /// Called from the canvas every frame.
    func step(to time: TimeInterval) {
        defer { lastTime = time }
        guard phase == .running, size.width > 0 else { return }
        let dt = CGFloat(min(1.0 / 30, max(0, time - (lastTime ?? time))))
        guard dt > 0 else { return }

        velocity -= Self.gravity * dt * (isSkidding && playerLift > 0 ? 1.8 : 1)
        playerLift += velocity * dt
        if playerLift <= 0 {
            playerLift = 0
            velocity = 0
        }

        distance += speed * dt
        speed = min(Self.maxSpeed, Self.startSpeed + distance / 55)

        for index in obstacles.indices { obstacles[index].x -= speed * dt }
        obstacles.removeAll { $0.x + $0.width < -30 }

        untilNextSpawn -= speed * dt
        if untilNextSpawn <= 0 {
            spawn()
            // Gaps widen with speed so every run stays jumpable.
            untilNextSpawn = CGFloat.random(in: 250...460) * (speed / Self.startSpeed) * 0.75
        }

        if obstacles.contains(where: { hitbox(of: $0).intersects(playerHitbox) }) {
            end()
        }
    }

    private func spawn() {
        let birdsAllowed = score > 250
        if birdsAllowed, Bool.random(), Int.random(in: 0..<3) == 0 {
            obstacles.append(Obstacle(kind: .bird, x: size.width + 20, width: 22, height: 16,
                                      lift: [CGFloat(14), 26].randomElement() ?? 14))
        } else {
            let tall = CGFloat.random(in: 16...28)
            let wide: CGFloat = Bool.random() ? 9 : 15
            obstacles.append(Obstacle(kind: .cactus, x: size.width + 20, width: wide, height: tall, lift: 0))
        }
    }

    private func end() {
        let final = score
        if final > best {
            best = final
            UserDefaults.standard.set(final, forKey: "runnerBest")
        }
        // Out of the render pass before the published change.
        DispatchQueue.main.async { [weak self] in self?.phase = .over }
    }

    // MARK: Geometry (screen space, y down)

    var playerRect: CGRect {
        let height = isSkidding && playerLift <= 0 ? Self.playerSize.height * 0.6 : Self.playerSize.height
        return CGRect(
            x: Self.playerX - Self.playerSize.width / 2,
            y: groundY - playerLift - height,
            width: Self.playerSize.width,
            height: height
        )
    }

    /// A little smaller than the drawing, so near misses feel fair.
    private var playerHitbox: CGRect { playerRect.insetBy(dx: 4, dy: 3) }

    func rect(of obstacle: Obstacle) -> CGRect {
        CGRect(x: obstacle.x, y: groundY - obstacle.lift - obstacle.height, width: obstacle.width, height: obstacle.height)
    }

    private func hitbox(of obstacle: Obstacle) -> CGRect {
        rect(of: obstacle).insetBy(dx: 2, dy: 2)
    }
}

/// The game surface: the canvas, and on top of it an AppKit view that takes
/// the clicks and the keys. The panel does not normally take the keyboard;
/// clicking this view makes it key (`needsPanelToBecomeKey`), which is what
/// lets Space reach the game at all.
struct RunnerGameView: View {
    /// A round started (true) or ended (false), so the panel can hold still.
    var onActiveChange: (Bool) -> Void

    @StateObject private var game = RunnerGame()

    private static let ink = Color(red: 0.85, green: 0.58, blue: 0.25)
    private static let groundLight = Color(red: 0.17, green: 0.69, blue: 0.31)
    private static let groundDark = Color(red: 0.12, green: 0.54, blue: 0.23)
    private static let cactus = Color(red: 0.75, green: 0.52, blue: 0.23)

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: game.phase != .running)) { context in
                Canvas { canvas, size in
                    game.size = size
                    game.step(to: context.date.timeIntervalSinceReferenceDate)
                    draw(in: &canvas, size: size)
                }
            }

            RunnerInputView(game: game)

            if game.phase != .running {
                Text(game.phase == .ready ? "CLICK / SPACE TO START" : "GAME OVER — CLICK TO RETRY")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: game.phase)
        .onChange(of: game.phase) { _, phase in onActiveChange(phase == .running) }
        .onDisappear { onActiveChange(false) }
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize) {
        let groundY = game.groundY

        // Ground, with pebbles that scroll so the speed reads.
        canvas.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: 3)), with: .color(Self.groundLight))
        canvas.fill(Path(CGRect(x: 0, y: groundY + 3, width: size.width, height: 6)), with: .color(Self.groundDark))
        let pebbleSpacing: CGFloat = 38
        let shift = game.distance.truncatingRemainder(dividingBy: pebbleSpacing)
        var x = -shift
        var pebble = 0
        while x < size.width {
            let y = groundY + 4 + CGFloat((pebble * 7) % 4)
            canvas.fill(Path(CGRect(x: x, y: y, width: 2, height: 1.5)), with: .color(Self.groundLight.opacity(0.6)))
            x += pebbleSpacing
            pebble += 1
        }

        // Obstacles.
        for obstacle in game.obstacles {
            let rect = game.rect(of: obstacle)
            switch obstacle.kind {
            case .cactus:
                canvas.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Self.cactus))
                let arm = CGRect(x: rect.maxX - 1, y: rect.minY + 5, width: 5, height: 3)
                canvas.fill(Path(roundedRect: arm, cornerRadius: 1.5), with: .color(Self.cactus))
            case .bird:
                canvas.draw(Text("🐦").font(.system(size: 17)),
                            at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }

        // The chicken, facing the way it runs, squashed while skidding.
        let player = game.playerRect
        var chicken = canvas
        chicken.translateBy(x: player.midX, y: player.maxY + 2)
        chicken.scaleBy(x: -1, y: game.isSkidding && game.playerLift <= 0 ? 0.62 : 1)
        chicken.draw(Text("🐔").font(.system(size: 21)), at: .zero, anchor: .bottom)

        // Score and hints in orange monospace.
        let mono = Font.system(size: 10.5, weight: .bold, design: .monospaced)
        canvas.draw(
            Text(String(format: "HI %05d  %05d", game.best, game.score)).font(mono).foregroundColor(Self.ink),
            at: CGPoint(x: size.width - 12, y: 10), anchor: .topTrailing
        )
        if game.phase != .running {
            canvas.draw(Text("SPACE — JUMP").font(mono).foregroundColor(Self.ink.opacity(0.8)),
                        at: CGPoint(x: 12, y: 10), anchor: .topLeading)
            canvas.draw(Text("HOLD ↓ — SKID").font(mono).foregroundColor(Self.ink.opacity(0.8)),
                        at: CGPoint(x: 12, y: 25), anchor: .topLeading)
        }
    }
}

/// Transparent AppKit view on top of the game that turns clicks and keys
/// into jumps and skids.
private struct RunnerInputView: NSViewRepresentable {
    let game: RunnerGame

    func makeNSView(context: Context) -> InputView {
        InputView(game: game)
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.game = game
    }

    final class InputView: NSView {
        var game: RunnerGame

        init(game: RunnerGame) {
            self.game = game
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            game.jump()
        }

        override func keyDown(with event: NSEvent) {
            switch Int(event.keyCode) {
            case 49, 126: // space, ↑
                if !event.isARepeat { game.jump() }
            case 125: // ↓
                game.setSkid(true)
            default:
                super.keyDown(with: event)
            }
        }

        override func keyUp(with event: NSEvent) {
            if Int(event.keyCode) == 125 { game.setSkid(false) }
        }
    }
}
