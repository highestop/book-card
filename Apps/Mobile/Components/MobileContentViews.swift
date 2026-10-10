import SwiftUI
import BookCardCore

struct MobileBookCard: View {
    let book: Book
    let progress: ReadingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(book.title, systemImage: "book.closed.fill").font(.headline)
            if !book.author.isEmpty { Text(book.author).font(.subheadline).foregroundStyle(.secondary) }
            if let progress {
                HStack {
                    Text(progress.percent == 100 ? "已读完" : progress.percent == 0 ? "未读" : "在读")
                    Spacer()
                    Text("\(progress.percent)%").monospacedDigit()
                }.font(.subheadline).foregroundStyle(progress.percent == 100 ? .green : .primary)
                ProgressView(value: Double(progress.percent), total: 100)
                if let duration = durationLabel(progress) {
                    Text(duration).font(.caption).foregroundStyle(.secondary)
                }
                if let time = progress.finishedAt, time > 0 {
                    Text("读完于 \(Date(timeIntervalSince1970: time).formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let time = progress.updatedAt, time > 0 {
                    Text("最近阅读 \(Date(timeIntervalSince1970: time).formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("进度待获取").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct MobileSourceRow: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title).font(.headline)
            Text("\(book.highlights ?? 0) 条划线 · \(book.thoughts ?? 0) 条想法")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct MobileSourceNotesView: View {
    @EnvironmentObject private var store: AppStore
    let book: Book
    @State private var kind = "全部"
    @State private var search = ""
    private var groups: [NoteGroup] { store.cache.noteGroups(for: book, kind: kind, search: search) }

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $kind) {
                    ForEach(["全部", "划线", "想法"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                if let detail = store.cache.details[book.id] {
                    Text("\(detail.highlightCount) 条划线 · \(detail.thoughtCount) 条想法")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.notes) { note in MobileNoteRow(note: note) }
                }
            }
            if let date = store.cache.details[book.id]?.synced {
                Section {
                    Text("本来源同步于 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索笔记或\(book.official ? "文章" : "章节")")
        .overlay {
            if store.cache.details[book.id] == nil {
                ContentUnavailableView(store.busy ? "正在同步，请稍候…" : "尚未同步该来源", systemImage: "arrow.clockwise")
                    .allowsHitTesting(false)
            } else if groups.isEmpty {
                ContentUnavailableView("暂无匹配笔记", systemImage: "quote.bubble")
                    .allowsHitTesting(false)
            }
        }
    }
}

struct MobileNoteRow: View {
    let note: Note
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(note.kind).font(.caption.bold()).foregroundStyle(.tint)
                Spacer()
                if let time = note.created {
                    Text(Date(timeIntervalSince1970: time).formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !note.quote.isEmpty { Text(note.quote).lineSpacing(5).textSelection(.enabled) }
            if let thought = note.thought { Text(thought).lineSpacing(5).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(.vertical, 8)
    }
}
