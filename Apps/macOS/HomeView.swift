import SwiftUI
import BookCardCore

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openShelf: () -> Void
    let openBook: (String) -> Void
    @State private var selectedID: String?
    private var entries: [NoteEntry] { store.cache.allNotes }
    private var index: Int { entries.firstIndex(where: { $0.id == selectedID }) ?? 0 }
    private var entry: NoteEntry? { entries.isEmpty ? nil : entries[index] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(title: "YOUR READING, KEPT CLOSE")
                        Text("读过的，留下来。").font(.system(size: 32, weight: .medium, design: .serif))
                        Text("重逢一段文字，也重逢当时的自己。")
                            .font(.system(size: 13)).foregroundStyle(Paper.secondary)
                    }
                    Spacer()
                    Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                        .font(.system(size: 11)).foregroundStyle(Paper.secondary).padding(.bottom, 3)
                }
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Label(index == 0 ? "最近一次标记" : "回顾书签", systemImage: "bookmark")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Paper.green)
                            Spacer()
                            if !entries.isEmpty { Text("\(index + 1) / \(entries.count)").monospacedDigit().font(.system(size: 11)).foregroundStyle(Paper.secondary) }
                        }
                        if let entry {
                            BookmarkCard(entry: entry, featured: true, openBook: { openBook(entry.book.id) })
                                .id(entry.id).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 10)))
                            HStack {
                                Button { step(-1) } label: { Label("更新一张", systemImage: "arrow.left") }
                                    .disabled(index == 0).buttonStyle(QuietButton())
                                Spacer()
                                if index > 0 {
                                    Button("回到最新") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedID = nil } }
                                        .buttonStyle(.plain).foregroundStyle(Paper.secondary)
                                }
                                Spacer()
                                Button { step(1) } label: { Label("往前翻阅", systemImage: "arrow.right") }
                                    .disabled(index >= entries.count - 1).buttonStyle(QuietButton())
                            }.font(.system(size: 11))
                        } else {
                            EmptyBookmarks(title: store.busy ? "正在整理你的书签…" : "第一张书签，等你留下", message: store.busy ? "笔记会逐本存入书架，稍等片刻。" : "在微信读书中划线或写下想法，\n回到这里便会自动同步。")
                                .frame(minHeight: 340).background(Paper.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.frame(maxWidth: .infinity)
                    shelfDoor.frame(width: 250)
                }
                HStack(spacing: 8) {
                    Rectangle().fill(Paper.line).frame(width: 28, height: 1)
                    Text("文字有了停靠的地方。").font(.system(size: 10)).tracking(2).foregroundStyle(Paper.secondary)
                }.padding(.top, 6)
            }.padding(42).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }.task { await store.refreshIfNeeded() }
    }
    private func step(_ delta: Int) {
        let destination = index + delta
        guard entries.indices.contains(destination) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { selectedID = entries[destination].id }
    }
    private var shelfDoor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Eyebrow(title: "THE BOOKSHELF")
            HStack(alignment: .bottom, spacing: -13) {
                ForEach(Array(store.cache.noteBooks.prefix(3).enumerated()), id: \.element.id) { index, book in
                    BookCover(book: book, compact: true).frame(width: 80, height: 120)
                        .rotationEffect(.degrees(Double(index - 1) * 7)).offset(y: index == 1 ? -8 : 0)
                }
                if store.cache.noteBooks.isEmpty {
                    Image(systemName: "books.vertical").font(.system(size: 65, weight: .ultraLight)).foregroundStyle(Paper.green.opacity(0.5)).frame(height: 120)
                }
            }.frame(maxWidth: .infinity).padding(.top, 13).padding(.bottom, 4).accessibilityHidden(true)
            Rectangle().fill(Paper.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("你的书签书架").font(.system(size: 21, weight: .medium, design: .serif))
                Text("\(store.cache.noteBooks.count) 本书与文集 · \(entries.count) 张书签")
                    .font(.system(size: 11)).foregroundStyle(Paper.secondary)
                Text("每一本书，都藏着\n让你停留过的句子。")
                    .font(.system(size: 12)).lineSpacing(6).foregroundStyle(Paper.secondary).padding(.top, 2)
            }
            Button(action: openShelf) {
                HStack { Text("打开全部书签"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 12, weight: .medium)).padding(14).foregroundStyle(Paper.card)
                    .background(Paper.green, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
        }.padding(24).background(Color(hex: 0xECEDE3), in: RoundedRectangle(cornerRadius: 12)).padding(.top, 31)
    }
}
