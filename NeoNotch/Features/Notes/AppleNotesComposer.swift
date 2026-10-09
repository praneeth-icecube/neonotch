import AppKit
import SwiftUI

/// Writes a new note straight into Apple Notes. No list and no history: what
/// you type becomes a note in Notes' default folder — its first line the
/// title — and the widget is clear for the next one.
///
/// Notes has no API for other apps, but it does have AppleScript, so the note
/// is made with `make new note`. macOS asks once whether NeoNotch may control
/// Notes; after that it simply works.
final class AppleNotesComposer: ObservableObject {
    enum Status: Equatable {
        case idle, saving
        case failed(String)
    }

    /// The note being written. Kept here, not in the editor, so the panel
    /// closing mid-sentence loses nothing.
    @Published var draft: String?
    @Published private(set) var status: Status = .idle

    /// Told when a note has landed in Notes.
    var onSaved: (() -> Void)?

    private let queue = DispatchQueue(label: "com.praneeth.NeoNotch.notes-app")

    var canSave: Bool {
        status != .saving && !(draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func begin() {
        if draft == nil { draft = "" }
        status = .idle
    }

    func discard() {
        draft = nil
        status = .idle
    }

    func save() {
        guard canSave, let text = draft?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        status = .saving
        let source = Self.script(for: text)
        // Off the main thread: the first time, the script waits on the
        // "control Notes" dialog until it is answered.
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let code = error?[NSAppleScript.errorNumber] as? Int
            Trace.log("notes-app", code.map { "save failed: \($0)" } ?? "saved")
            DispatchQueue.main.async {
                switch code {
                case nil:
                    self.draft = nil
                    self.status = .idle
                    self.onSaved?()
                case .some(-1743):
                    self.status = .failed("Allow NeoNotch to control Notes")
                default:
                    self.status = .failed("Notes didn't take it (\(code ?? 0))")
                }
            }
        }
    }

    /// Privacy & Security → Automation, where "Don't Allow" can be undone.
    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The note as Notes stores it — one `<div>` per line — escaped for HTML
    /// and then for an AppleScript string, so nothing typed can break out.
    static func script(for text: String) -> String {
        let html = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? "<div><br></div>" : "<div>\($0)</div>" }
            .joined()
        let literal = html
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Notes"
            make new note at default folder of default account with properties {body:"\(literal)"}
        end tell
        """
    }
}

/// Home's Notes: "New note", then a page to write on and Save. The note goes
/// to Apple Notes; nothing stays behind here.
struct AppleNotesModuleView: View {
    @ObservedObject var composer: AppleNotesComposer
    /// Tells the panel typing started or stopped, so it can take the keyboard
    /// and stay open while you write.
    var onEditingChanged: (Bool) -> Void

    @FocusState private var isEditorFocused: Bool

    /// Notes' own yellow.
    private static let notesYellow = Color(red: 1, green: 214 / 255, blue: 10 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.secondary)

            if composer.draft != nil {
                editor.transition(.opacity)
            } else {
                prompt.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: composer.draft == nil)
        .onChange(of: composer.draft == nil) { _, isClosed in
            onEditingChanged(!isClosed)
        }
    }

    private var prompt: some View {
        VStack(spacing: 8) {
            Button {
                composer.begin()
            } label: {
                VStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Self.notesYellow)
                    Text("New note")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Write a note — it is saved to Apple Notes")

            if case .failed(let reason) = composer.status {
                failure(reason)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if (composer.draft ?? "").isEmpty {
                    Text("New note…")
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTheme.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { composer.draft ?? "" },
                    set: { composer.draft = $0 }
                ))
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($isEditorFocused)
                .disabled(composer.status == .saving)
            }
            .frame(maxHeight: .infinity)

            if case .failed(let reason) = composer.status {
                failure(reason)
            }

            HStack(spacing: 7) {
                Button {
                    composer.discard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(NotchTheme.fill))
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .foregroundStyle(NotchTheme.primary)
                .help("Discard")

                Spacer(minLength: 0)

                Button {
                    composer.save()
                } label: {
                    Group {
                        if composer.status == .saving {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Save")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 58, height: 24)
                    .background(Capsule().fill(Self.notesYellow))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.95))
                .disabled(!composer.canSave)
                .opacity(composer.canSave || composer.status == .saving ? 1 : 0.45)
                .help("Save to Apple Notes")
            }
        }
        .onAppear { isEditorFocused = true }
    }

    private func failure(_ reason: String) -> some View {
        Button {
            composer.openAutomationSettings()
        } label: {
            Text(reason)
                .font(.system(size: 9.5))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.42))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .help("Open Privacy & Security → Automation")
    }
}
