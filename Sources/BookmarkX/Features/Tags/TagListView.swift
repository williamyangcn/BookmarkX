import SwiftUI

struct TagListView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let tags = appModel.bookmarkStore?.tags ?? []

        Group {
            if tags.isEmpty {
                ContentUnavailableView("tags.emptyTitle", systemImage: "tag", description: Text("tags.emptyDescription"))
            } else {
                List(tags) { tag in
                    HStack(spacing: 10) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: tag.colorHex) ?? .accentColor)
                            .frame(width: 20)
                        Text(tag.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("sidebar.tags")
    }
}
