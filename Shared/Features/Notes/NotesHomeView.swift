import SwiftData
import SwiftUI
import TrueFocusKit

/// The Notes space: a place to brainstorm and plan, with checklists you can cross off.
/// iPhone: a list that pushes the editor. Mac: list and editor side by side.
struct NotesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""
    /// The note just composed, until @Query catches up with it.
    @State private var freshNote: Note?
    #if os(iOS)
    @State private var path: [UUID] = []
    #else
    @State private var selection: UUID?
    #endif

    var body: some View {
        #if os(iOS)
        NavigationStack(path: $path) {
            listContent
                .navigationTitle("Notes")
                .searchable(text: $search, prompt: "Search")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { composeButton }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let note = note(id) {
                        NoteEditorView(note: note)
                    } else {
                        TF.Palette.paper.ignoresSafeArea()
                    }
                }
                .tfPage()
        }
        .tint(TF.Palette.ink)
        .onAppear { removeEmptyNotes(keeping: Set(path)) }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { removeEmptyNotes(keeping: []) }
        }
        #else
        NavigationSplitView {
            listContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 420)
                .searchable(text: $search, placement: .sidebar, prompt: "Search")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { composeButton }
                }
                .onDeleteCommand {
                    if let id = selection, let note = note(id) { delete(note) }
                }
        } detail: {
            if let id = selection, let note = note(id) {
                NoteEditorView(note: note, onDelete: { selection = nil })
                    .id(note.id)
            } else {
                emptyDetail
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            if let oldValue, oldValue != newValue {
                removeEmptyNotes(keeping: newValue.map { [$0] } ?? [], only: oldValue)
            }
        }
        #endif
    }

    // MARK: Data

    private func note(_ id: UUID) -> Note? {
        if let found = notes.first(where: { $0.id == id }) { return found }
        if let freshNote, freshNote.id == id, !freshNote.isDeleted { return freshNote }
        return nil
    }

    private var filtered: [Note] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.body.localizedCaseInsensitiveContains(query) }
    }

    private var pinned: [Note] { filtered.filter(\.isPinned) }
    private var unpinned: [Note] { filtered.filter { !$0.isPinned } }

    // MARK: List

    @ViewBuilder
    private var listContent: some View {
        if notes.isEmpty {
            emptyState
        } else {
            #if os(iOS)
            List {
                sections
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            #else
            List(selection: $selection) {
                sections
            }
            .listStyle(.sidebar)
            #endif
        }
    }

    @ViewBuilder
    private var sections: some View {
        if !pinned.isEmpty {
            Section {
                rows(pinned)
            } header: {
                Text("Pinned").tfEyebrowStyle()
            }
        }
        Section {
            rows(unpinned)
        } header: {
            if !pinned.isEmpty {
                Text("Notes").tfEyebrowStyle()
            }
        }
        if filtered.isEmpty {
            Text("No results for “\(search)”")
                .font(.subheadline)
                .foregroundStyle(TF.Palette.ink2)
        }
    }

    private func rows(_ list: [Note]) -> some View {
        ForEach(list) { note in
            row(note)
                .contextMenu {
                    Button {
                        togglePin(note)
                    } label: {
                        Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                    }
                    Button(role: .destructive) {
                        delete(note)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    @ViewBuilder
    private func row(_ note: Note) -> some View {
        #if os(iOS)
        NavigationLink(value: note.id) {
            NoteRow(note: note)
        }
        .listRowBackground(TF.Palette.surface)
        .swipeActions(edge: .leading) {
            Button {
                togglePin(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(TF.Palette.signal)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        #else
        NoteRow(note: note)
            .tag(note.id)
        #endif
    }

    private var composeButton: some View {
        Button(action: compose) {
            Label("New Note", systemImage: "square.and.pencil")
        }
        .keyboardShortcut("n", modifiers: [.command, .option])
        .help("New Note (⌥⌘N)")
    }

    // MARK: Empty states

    private var emptyState: some View {
        VStack(spacing: TF.Space.m) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(TF.Palette.ink3)
                .padding(.bottom, TF.Space.xs)
            Text("Empty your head.")
                .font(.tfTitle)
                .foregroundStyle(TF.Palette.ink)
            Text("Brainstorm, plan, and cross things off.")
                .font(.subheadline)
                .foregroundStyle(TF.Palette.ink2)
            Button("New Note", action: compose)
                .buttonStyle(QuietButtonStyle())
                .padding(.top, TF.Space.s)
        }
        .multilineTextAlignment(.center)
        .padding(TF.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if os(macOS)
    private var emptyDetail: some View {
        VStack(spacing: TF.Space.s) {
            Text("No note selected")
                .font(.tfTitle)
                .foregroundStyle(TF.Palette.ink2)
            Text("Press ⌘N to start one.")
                .font(.subheadline)
                .foregroundStyle(TF.Palette.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TF.Palette.paper)
    }
    #endif

    // MARK: Actions

    private func compose() {
        search = ""
        let note = Note()
        modelContext.insert(note)
        try? modelContext.save()
        freshNote = note
        #if os(iOS)
        path.append(note.id)
        #else
        selection = note.id
        #endif
    }

    private func togglePin(_ note: Note) {
        withAnimation(TF.Motion.snappy) {
            note.isPinned.toggle()
        }
        try? modelContext.save()
    }

    private func delete(_ note: Note) {
        #if os(macOS)
        if selection == note.id { selection = nil }
        #endif
        withAnimation(TF.Motion.snappy) {
            modelContext.delete(note)
        }
        try? modelContext.save()
    }

    /// Notes deletes notes you never typed in. So do we, once you've left them.
    /// Runs a beat later so a closing editor can flush its last keystrokes first.
    private func removeEmptyNotes(keeping keep: Set<UUID>, only target: UUID? = nil) {
        let context = modelContext
        let candidates = notes
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            var changed = false
            for note in candidates where !note.isDeleted && !keep.contains(note.id) && (target == nil || note.id == target) {
                if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    context.delete(note)
                    changed = true
                }
            }
            if changed { try? context.save() }
        }
    }
}

/// A list row: title, then date and the first line of text, like Notes.
struct NoteRow: View {
    var note: Note

    var body: some View {
        let document = note.document
        let progress = document.checklistProgress
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TF.Palette.signal)
                }
                Text(document.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TF.Palette.ink)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(NoteDates.short(note.updatedAt))
                    .foregroundStyle(TF.Palette.ink)
                Text(document.preview)
                    .foregroundStyle(TF.Palette.ink2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if progress.total > 0 {
                    ChecklistBadge(done: progress.done, total: progress.total)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// "3/7" with a tiny progress ring; Ember when everything is crossed off.
struct ChecklistBadge: View {
    var done: Int
    var total: Int

    var body: some View {
        let complete = total > 0 && done == total
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(TF.Palette.hairline, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                    .stroke(TF.Palette.signal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)
            Text("\(done)/\(total)")
                .font(.tfCaption)
                .foregroundStyle(complete ? TF.Palette.signal : TF.Palette.ink2)
        }
        .accessibilityLabel("\(done) of \(total) checked")
    }
}

/// Apple Notes–style row dates: time today, "Yesterday", weekday this week, then the date.
enum NoteDates {
    static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                              to: calendar.startOfDay(for: now)).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
