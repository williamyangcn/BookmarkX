import AppKit
import SwiftUI

/// Small in-memory avatar cache so list rows don't refetch on every re-render.
private final class AvatarCacheBox: @unchecked Sendable {
    let cache = NSCache<NSURL, NSImage>()
}

enum AvatarImageCache {
    private static let box = AvatarCacheBox()

    static func image(for url: URL) -> NSImage? {
        box.cache.object(forKey: url as NSURL)
    }

    static func store(_ image: NSImage, for url: URL) {
        box.cache.setObject(image, forKey: url as NSURL)
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var fallback: () -> AnyView

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback()
                    .task(id: url) { await load() }
            }
        }
        .frame(width: width, height: height)
    }

    private func load() async {
        guard let url else { return }
        if let cached = AvatarImageCache.image(for: url) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let loaded = NSImage(data: data) else { return }
            AvatarImageCache.store(loaded, for: url)
            image = loaded
        } catch {
            return
        }
    }
}
