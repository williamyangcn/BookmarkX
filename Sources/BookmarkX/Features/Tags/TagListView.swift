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
                    Label(tag.name, systemImage: "tag")
                }
            }
        }
        .navigationTitle("sidebar.tags")
    }
}
