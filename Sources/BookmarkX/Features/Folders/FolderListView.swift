import SwiftUI

struct FolderListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var newFolderName = ""

    var body: some View {
        let folders = appModel.bookmarkStore?.folders ?? []

        VStack(spacing: 0) {
            HStack {
                TextField("folders.newPlaceholder", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                Button("folders.create") {
                    try? appModel.bookmarkStore?.createFolder(named: newFolderName)
                    newFolderName = ""
                    Task { await appModel.reloadBookmarks() }
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            if folders.isEmpty {
                ContentUnavailableView("folders.emptyTitle", systemImage: "folder", description: Text("folders.emptyDescription"))
            } else {
                List(folders) { folder in
                    Label(folder.name, systemImage: "folder")
                }
            }
        }
        .navigationTitle("sidebar.folders")
    }
}
