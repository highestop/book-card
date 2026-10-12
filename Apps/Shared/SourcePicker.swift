import SwiftUI
import BookCardCore

struct SourcePicker: View {
    let books: [Book]
    @Binding var selection: String?
    private var selected: Book? { books.first { $0.id == selection } }

    var body: some View {
        Menu {
            option("所有书名／公众号", id: nil)
            Divider()
            ForEach(books) { book in
                option(book.title + (book.official ? " · 公众号" : (book.author.isEmpty ? "" : " · " + book.author)), id: book.id)
            }
        } label: {
            Label(selected?.title ?? "所有书名／公众号", systemImage: "line.3.horizontal.decrease")
                .font(.subheadline).lineLimit(1)
        }
        .menuStyle(.borderlessButton).menuIndicator(.visible)
        .padding(12).frame(maxWidth: .infinity)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityLabel("按书名或公众号筛选")
        .accessibilityValue(selected?.title ?? "所有书名／公众号")
        .onChange(of: books.map(\.id), initial: true) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    private func option(_ title: String, id: String?) -> some View {
        Button { selection = id } label: {
            if selection == id { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }
}
