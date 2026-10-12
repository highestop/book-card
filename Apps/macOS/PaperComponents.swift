import SwiftUI
import BookCardCore
import AppKit

enum Paper {
    static let background = Color(hex: 0xF5F3EC)
    static let card = Color(hex: 0xFFFEFA)
    static let ink = Color(hex: 0x293B34)
    static let secondary = Color(hex: 0x787D73)
    static let line = Color(hex: 0xDEDCD1)
    static let green = Color(hex: 0x3F6252)
    static let rust = Color(hex: 0xAD6245)
    static let covers: [Color] = [Color(hex: 0x3E5B50), Color(hex: 0xB5805E), Color(hex: 0x61747C), Color(hex: 0x807564), Color(hex: 0x795C60), Color(hex: 0x5B6750)]
    static func color(for id: String) -> Color {
        covers[id.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff } % covers.count]
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
struct Ribbon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero); path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.height - rect.width * 0.3))
            path.addLine(to: CGPoint(x: 0, y: rect.height)); path.closeSubpath()
        }
    }
}
struct QuietButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 15).padding(.vertical, 10)
            .background(Paper.card.opacity(configuration.isPressed ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Paper.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}
struct Eyebrow: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 10, weight: .medium)).tracking(2.5).foregroundStyle(Paper.secondary) }
}
struct SearchBox: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(Paper.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Paper.secondary) }
                    .buttonStyle(.plain).help("清除搜索")
            }
        }.padding(12).background(Paper.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Paper.line, lineWidth: 1))
    }
}
struct EmptyBookmarks: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bookmark").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Paper.green)
            Text(title).font(.system(size: 22, weight: .medium, design: .serif))
            Text(message).font(.system(size: 13)).lineSpacing(5).foregroundStyle(Paper.secondary).multilineTextAlignment(.center)
        }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BookmarkCard: View {
    let entry: NoteEntry
    var featured = false
    var openBook: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var copied = false
    private var color: Color { Paper.color(for: entry.book.id) }
    private var long: Bool {
        (entry.quoteText.map { NoteText.excerpt($0, limit: 220) != $0 } ?? false) ||
        (entry.thoughtText.map { NoteText.excerpt($0, limit: 160) != $0 } ?? false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: featured ? 24 : 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.book.official ? "newspaper" : "book.closed")
                        Text(entry.book.official ? "公众号 · " + entry.note.kind : "读书笔记 · " + entry.note.kind)
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(color)
                    if let openBook {
                        Button(action: openBook) { Text(entry.book.title).font(.system(size: featured ? 19 : 16, weight: .semibold, design: .serif)).multilineTextAlignment(.leading) }
                            .buttonStyle(.plain).help("打开这本书的全部书签")
                    } else { Text(entry.book.title).font(.system(size: featured ? 19 : 16, weight: .semibold, design: .serif)) }
                    Text(entry.chapterTitle).font(.system(size: 11)).foregroundStyle(Paper.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 20)
                Image(systemName: "quote.opening").font(.system(size: featured ? 29 : 22, weight: .light)).foregroundStyle(color.opacity(0.38)).padding(.top, 4)
            }.padding(.trailing, 26)
            Rectangle().fill(Paper.line.opacity(0.7)).frame(height: 1)
            if let quote = entry.quoteText {
                Text(featured || expanded ? quote : NoteText.excerpt(quote, limit: 220)).font(.system(size: featured ? 23 : 17, weight: .regular, design: .serif))
                    .lineSpacing(featured ? 11 : 7)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let thought = entry.thoughtText {
                VStack(alignment: .leading, spacing: 10) {
                    Label("我的想法", systemImage: "pencil.tip").font(.system(size: 10, weight: .medium)).foregroundStyle(Paper.rust)
                    Text(featured || expanded ? thought : NoteText.excerpt(thought, limit: 160)).font(.system(size: featured ? 14 : 13)).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xF5F0E6), in: RoundedRectangle(cornerRadius: 8))
            }
            if entry.quoteText == nil && entry.thoughtText == nil {
                Label("这条标记包含图片或暂无可显示的文字", systemImage: "photo")
                    .font(.system(size: 13)).foregroundStyle(Paper.secondary).padding(.vertical, 28)
            }
            if !featured && long {
                Button(expanded ? "收起全文 ↑" : "展开全文 ↓") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            }
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 10))
                    if let time = entry.note.created, time > 0 {
                        Text(readingDate(Date(timeIntervalSince1970: time)))
                    } else { Text("标记时间未提供") }
                }.font(.system(size: 10)).foregroundStyle(Paper.secondary)
                Spacer(minLength: 12)
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.copyText, forType: .string)
                    copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 12)).frame(width: 26, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(Paper.secondary).help(copied ? "已复制" : "复制书签及来源")
                    .accessibilityLabel(copied ? "已复制书签" : "复制书签及来源")
                    .task(id: copied) {
                        guard copied else { return }
                        do { try await Task.sleep(for: .seconds(2)); copied = false } catch { }
                    }
            }.padding(.top, featured ? 12 : 0)
        }.padding(featured ? 36 : 26).frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Paper.line.opacity(0.75), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Ribbon().fill(color).frame(width: 22, height: featured ? 59 : 45).padding(.trailing, featured ? 34 : 24)
                    .accessibilityHidden(true)
            }
            .shadow(color: Paper.ink.opacity(featured ? 0.07 : 0.025), radius: featured ? 24 : 12, x: 0, y: 9)
    }
}

struct BookCover: View {
    let book: Book
    var compact = false
    private var color: Color { Paper.color(for: book.id) }
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(color.gradient)
            Rectangle().fill(.black.opacity(0.12)).frame(width: 9).padding(.leading, 5)
            Rectangle().fill(.white.opacity(0.15)).frame(width: 1).padding(.leading, 14)
            VStack(alignment: .leading, spacing: compact ? 8 : 15) {
                Text(book.official ? "ARTICLES & NOTES" : "READING & NOTES")
                    .font(.system(size: compact ? 5 : 7, weight: .medium)).tracking(compact ? 0.5 : 1.8).opacity(0.65)
                Rectangle().fill(.white.opacity(0.35)).frame(width: compact ? 20 : 32, height: 1)
                Text(book.title).font(.system(size: compact ? 15 : 23, weight: .medium, design: .serif))
                    .lineSpacing(5).lineLimit(compact ? 3 : 4).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Text(book.official ? "公众号文集" : (book.author.isEmpty ? "阅读札记" : book.author))
                    .font(.system(size: compact ? 7 : 10)).lineLimit(2).opacity(0.75)
                if !compact { Image(systemName: book.official ? "newspaper" : "leaf").font(.system(size: 18, weight: .ultraLight)).opacity(0.55) }
            }.foregroundStyle(Color(hex: 0xF5F0DE)).padding(.leading, compact ? 22 : 30).padding(.trailing, 15).padding(.vertical, compact ? 18 : 26)
        }
        .overlay(alignment: .topTrailing) { Ribbon().fill(Paper.rust).frame(width: compact ? 10 : 16, height: compact ? 28 : 40).padding(.trailing, compact ? 13 : 19) }
        .overlay(alignment: .trailing) { UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3).fill(Color(hex: 0xEAE4D4)).frame(width: 4).padding(.vertical, 5) }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.16), radius: compact ? 5 : 10, x: 5, y: 7)
        .accessibilityElement(children: .ignore).accessibilityLabel(book.title)
    }
}
