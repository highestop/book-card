import SwiftUI
import BookCardCore

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openBookmarks: () -> Void
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
                            Label(selectedID == nil ? "最近一次标记" : "随机重逢", systemImage: selectedID == nil ? "bookmark" : "shuffle")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Paper.green)
                            Spacer()
                            if selectedID != nil {
                                Button("回到最新") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedID = nil } }
                                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Paper.secondary)
                            }
                            Button(action: randomize) { Label("随机一张", systemImage: "shuffle") }
                                .font(.system(size: 11)).disabled(entries.count < 2).buttonStyle(QuietButton())
                        }
                        if let entry {
                            BookmarkCard(entry: entry, featured: true, openBook: { openBook(entry.book.id) })
                                .id(entry.id).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 10)))
                        } else {
                            EmptyBookmarks(title: store.busy ? "正在整理你的书签…" : "第一张书签，等你留下", message: store.busy ? "笔记会逐本存入本机，稍等片刻。" : "在微信读书中划线或写下想法，\n回到这里便会自动同步。")
                                .frame(minHeight: 340).background(Paper.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.frame(maxWidth: .infinity)
                    collectionDoor.frame(width: 250)
                }
                HStack(spacing: 8) {
                    Rectangle().fill(Paper.line).frame(width: 28, height: 1)
                    Text("文字有了停靠的地方。").font(.system(size: 10)).tracking(2).foregroundStyle(Paper.secondary)
                }.padding(.top, 6)
            }.padding(42).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }.task { await store.refreshIfNeeded() }
    }
    private func randomize() {
        guard let next = store.cache.randomBookmark(excluding: entry?.id) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { selectedID = next.id }
    }
    private var collectionDoor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Eyebrow(title: "THE COLLECTION")
            ZStack {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 8).fill(index == 2 ? Paper.card : Paper.card.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Paper.line, lineWidth: 1))
                        .overlay(alignment: .topTrailing) {
                            Ribbon().fill(Paper.green.opacity(index == 2 ? 1 : 0.45)).frame(width: 14, height: 32).padding(.trailing, 16)
                        }
                        .overlay(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(0..<3) { line in Capsule().fill(Paper.green.opacity(0.15)).frame(width: line == 2 ? 48 : 80, height: 3) }
                            }.padding(20)
                        }
                        .frame(width: 150, height: 108)
                        .rotationEffect(.degrees(Double(index - 2) * -8))
                        .offset(x: CGFloat(index - 2) * -5, y: CGFloat(index - 2) * 9)
                }
            }.frame(maxWidth: .infinity).frame(height: 140).accessibilityHidden(true)
            Rectangle().fill(Paper.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("你的书签集").font(.system(size: 21, weight: .medium, design: .serif))
                Text("\(store.cache.noteBooks.count) 本书与文集 · \(entries.count) 张书签")
                    .font(.system(size: 11)).foregroundStyle(Paper.secondary)
                Text("那些让你停留的句子，\n都在这里等你重读。")
                    .font(.system(size: 12)).lineSpacing(6).foregroundStyle(Paper.secondary).padding(.top, 2)
            }
            Button(action: openBookmarks) {
                HStack { Text("打开全部书签"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 12, weight: .medium)).padding(14).foregroundStyle(Paper.card)
                    .background(Paper.green, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
        }.padding(24).background(Color(hex: 0xECEDE3), in: RoundedRectangle(cornerRadius: 12)).padding(.top, 51)
    }
}
