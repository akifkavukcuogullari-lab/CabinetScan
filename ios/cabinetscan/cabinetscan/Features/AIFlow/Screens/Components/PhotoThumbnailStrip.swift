//
//  PhotoThumbnailStrip.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import SwiftUI

/// Horizontal strip displaying captured photo thumbnails.
/// Per Story 2.5 - Task 6.5, 6.6, Task 7.3, UX-13
struct PhotoThumbnailStrip: View {
    /// Array of captured photos with thumbnails
    let photos: [PhotoThumbnailItem]

    /// Callback when a thumbnail is tapped
    let onTap: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Constants

    /// Thumbnail size (ensuring 44pt minimum touch target - UX-19)
    private let thumbnailSize: CGFloat = 60

    /// Spacing between thumbnails
    private let thumbnailSpacing: CGFloat = 12

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: thumbnailSpacing) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, item in
                    PhotoThumbnailView(
                        item: item,
                        index: index,
                        size: thumbnailSize,
                        onTap: { onTap(index) }
                    )
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                }

                // Empty slots for remaining photos
                ForEach(photos.count..<5, id: \.self) { index in
                    EmptyThumbnailSlot(index: index, size: thumbnailSize)
                }
            }
            .padding(.horizontal, 20)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: photos.count)
        }
        .frame(height: thumbnailSize + 16) // Extra padding for border/shadow
    }
}

// MARK: - Thumbnail Item

/// Data model for a thumbnail in the strip
struct PhotoThumbnailItem: Identifiable, Equatable {
    let id: UUID
    let thumbnail: UIImage
    let isBlurry: Bool

    static func == (lhs: PhotoThumbnailItem, rhs: PhotoThumbnailItem) -> Bool {
        lhs.id == rhs.id && lhs.isBlurry == rhs.isBlurry
    }
}

// MARK: - Individual Thumbnail View

private struct PhotoThumbnailView: View {
    let item: PhotoThumbnailItem
    let index: Int
    let size: CGFloat
    let onTap: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Thumbnail image
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Blur warning indicator (yellow border) - Task 4.4
                if item.isBlurry {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow, lineWidth: 3)
                        .frame(width: size, height: size)

                    // Small warning icon
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .frame(width: size, height: size)
                    .padding(4)
                } else {
                    // Normal border
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: size, height: size)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.8)
        .onAppear {
            // Fade-in animation (0.2s per UX-13)
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
        .accessibilityLabel("Photo \(index + 1)\(item.isBlurry ? ", blurry" : "")")
        .accessibilityHint("Tap to preview")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Empty Slot View

private struct EmptyThumbnailSlot: View {
    let index: Int
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                    .foregroundStyle(Color.white.opacity(0.3))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Empty Strip") {
    ZStack {
        Color.black
        PhotoThumbnailStrip(
            photos: [],
            onTap: { index in print("Tapped \(index)") }
        )
    }
}

#Preview("With Photos") {
    ZStack {
        Color.black
        PhotoThumbnailStrip(
            photos: [
                PhotoThumbnailItem(id: UUID(), thumbnail: UIImage(systemName: "photo")!, isBlurry: false),
                PhotoThumbnailItem(id: UUID(), thumbnail: UIImage(systemName: "photo.fill")!, isBlurry: true),
                PhotoThumbnailItem(id: UUID(), thumbnail: UIImage(systemName: "photo")!, isBlurry: false)
            ],
            onTap: { index in print("Tapped \(index)") }
        )
    }
}
