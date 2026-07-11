import SwiftUI
import UIKit

extension LibraryItem {
    var preferredArtwork: ArtworkAsset? {
        let available = artworkAssets ?? []
        if let preferredArtworkID,
           let preferred = available.first(where: { $0.id == preferredArtworkID }) {
            return preferred
        }
        return available.sorted { $0.createdAt < $1.createdAt }.first
    }

    var coverAspectRatio: CGFloat {
        if let ratio = preferredArtwork?.aspectRatio, ratio > 0.2, ratio < 3 {
            return ratio
        }
        return mediaKind.defaultCoverAspectRatio
    }
}

struct CoverArtworkView: View {
    let item: LibraryItem
    var contentMode = ContentMode.fill

    var body: some View {
        CachedArtworkView(
            asset: item.preferredArtwork,
            mediaKind: item.mediaKind,
            contentMode: contentMode
        )
        .accessibilityLabel("Cover for \(item.title)")
    }
}

private struct CachedArtworkView: View {
    let asset: ArtworkAsset?
    let mediaKind: MediaKind
    let contentMode: ContentMode

    @Environment(AppServices.self) private var services
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ArtworkPlaceholder(mediaKind: mediaKind, didFail: didFail)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: loadID(for: proxy.size)) {
                await load(targetSize: proxy.size)
            }
            .animation(.easeInOut(duration: 0.18), value: image != nil)
        }
    }

    private func loadID(for size: CGSize) -> ArtworkLoadID {
        ArtworkLoadID(
            assetID: asset?.id,
            updatedAt: asset?.updatedAt,
            pixelWidth: Int(size.width * displayScale),
            pixelHeight: Int(size.height * displayScale)
        )
    }

    private func load(targetSize: CGSize) async {
        guard targetSize.width > 1, targetSize.height > 1, let asset else {
            image = nil
            didFail = false
            return
        }

        image = nil
        didFail = false

        do {
            let data: Data
            if let imageData = asset.imageData {
                data = imageData
            } else if let value = asset.remoteURLString, let url = URL(string: value) {
                data = try await services.artwork.data(for: url, cacheKey: asset.cacheKey)
            } else {
                return
            }

            try Task.checkCancellation()
            image = await ArtworkDownsampler.image(
                from: data,
                targetSize: targetSize,
                displayScale: displayScale
            )
            didFail = image == nil
        } catch is CancellationError {
            // A recycled grid cell should stop quietly.
        } catch {
            didFail = true
        }
    }
}

private struct ArtworkLoadID: Hashable {
    let assetID: UUID?
    let updatedAt: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

private struct ArtworkPlaceholder: View {
    let mediaKind: MediaKind
    let didFail: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    mediaKind.accentColor.opacity(0.72),
                    WhatFunTheme.raisedBackground,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: didFail ? "wifi.slash" : mediaKind.symbolName)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(WhatFunTheme.ink.opacity(0.72))
                .accessibilityHidden(true)
        }
    }
}

