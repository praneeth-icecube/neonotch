import SwiftUI

/// Quick notes. "What's on your mind?" opens the editor; each
/// note shows its colour as a bar underneath and a circle to tick it off.
/// Once connected, the list is your Apple Reminders.
struct NotesModuleView: View {
    @ObservedObject var notes: NotesModel
    var canRephrase: Bool
    /// Tells the panel that typing started or stopped, so it can take the
    /// keyboard and stay open while you write.
    var onEditingChanged: (Bool) -> Void

    @StateObject private var ai = AIRequest()
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        ZStack {
            if notes.draft != nil {
                editor.transition(.opacity)
            } else {
                list.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: notes.draft == nil)
        .onChange(of: notes.draft == nil) { _, isClosed in
            onEditingChanged(!isClosed)
            if isClosed { ai.dismiss() }
        }
        .onChange(of: ai.state) { _, state in
            if case .done(_, let text) = state {
                notes.draft?.text = text
                ai.dismiss()
            }
        }
    }

    // MARK: List

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Text("Reminders")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchTheme.secondary)
                    Spacer(minLength: 0)
                    Button {
                        notes.beginNew()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotchTheme.primary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(NotchTheme.fill))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .help(notes.isUsingReminders
                          ? "New reminder — saved to “\(notes.listName ?? "Reminders")”"
                          : "New reminder")
                }
                .padding(.bottom, 1)

                if !notes.isUsingReminders {
                    syncButton
                } else if notes.sortedNotes.isEmpty {
                    Text("Nothing to do")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.tertiary)
                }

                ForEach(notes.sortedNotes) { note in
                    NoteRow(
                        note: note,
                        onToggle: { withAnimation(.notchSpring) { notes.toggleDone(note) } },
                        onEdit: { notes.beginEditing(note) },
                        onDelete: { withAnimation(.notchSpring) { notes.delete(note) } }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Until Reminders is connected the notes stay on this Mac; this connects
    /// it, or — once refused — opens the pane where it can be allowed.
    private var syncButton: some View {
        let denied = notes.remindersAccess == .denied
        return Button {
            notes.connectReminders()
        } label: {
            Label(denied ? "Reminders is off" : "Sync with Reminders", systemImage: "checklist")
        }
        .buttonStyle(NotchPillButtonStyle(compact: true))
        .help(denied
              ? "Allow NeoNotch under Privacy & Security → Reminders"
              : "Show your Apple Reminders here — add and tick off from either side")
    }

    // MARK: Editor

    private var draftText: Binding<String> {
        Binding(
            get: { notes.draft?.text ?? "" },
            set: { notes.draft?.text = $0 }
        )
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if draftText.wrappedValue.isEmpty {
                        Text("New reminder…")
                            .font(.system(size: 12))
                            .foregroundStyle(NotchTheme.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: draftText)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .focused($isEditorFocused)
                        .disabled(ai.isWorking)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 7) {
                    actionButton("xmark", help: "Discard") { notes.discardDraft() }
                    actionButton("checkmark", help: "Save") {
                        withAnimation(.notchSpring) { notes.commitDraft() }
                    }
                    if canRephrase {
                        Button(action: rephrase) {
                            ZStack {
                                if ai.isWorking {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(NotchTheme.fill))
                            .contentShape(Circle())
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(ai.isWorking || draftText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Rephrase with Apple Intelligence")
                    }
                    Spacer(minLength: 0)
                }
                if case .failed(let reason) = ai.state {
                    Text(reason)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.42))
                        .lineLimit(2)
                }
            }

            VStack(spacing: 6) {
                ForEach(NoteColor.allCases) { color in
                    let isSelected = notes.draft?.color == color
                    Button {
                        notes.draft?.color = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 2 : 0).padding(-3))
                            .padding(3)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.85))
                }
            }
            .padding(.top, 2)
        }
        .onAppear { isEditorFocused = true }
    }

    private func actionButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(NotchTheme.fill))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(NotchTheme.primary)
        .help(help)
    }

    private func rephrase() {
        let text = draftText.wrappedValue
        ai.run("Rephrase") { try await AIAssistant.perform(.rephrase, on: text) }
    }
}

private struct NoteRow: View {
    let note: Note
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.text)
                    .font(.system(size: 12))
                    .lineSpacing(1.5)
                    .lineLimit(3)
                    .strikethrough(note.isDone, color: NotchTheme.tertiary)
                    .foregroundStyle(note.isDone ? NotchTheme.tertiary : NotchTheme.primary)
                HStack(spacing: 4) {
                    Text(note.age)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.56))
                    Spacer(minLength: 0)
                    if isHovering {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.42))
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                        .transition(.opacity)
                    }
                }
                Capsule()
                    .fill(note.color.color)
                    .frame(height: 2.5)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Button(action: onToggle) {
                Image(systemName: note.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(note.isDone ? note.color.color : NotchTheme.secondary)
            }
            .buttonStyle(PressScaleStyle(scale: 0.85))
            .help(note.isDone ? "Mark as not done" : "Mark as done")
        }
        .opacity(note.isDone ? 0.7 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}
