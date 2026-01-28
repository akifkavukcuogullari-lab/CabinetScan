//
//  PhotoPreviewSheet.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import SwiftUI
import UIKit

/// Full-screen photo preview with delete option.
/// Per Story 2.5 - Task 6.7, 6.8
struct PhotoPreviewSheet: View {
    /// The photo to preview
    let photo: PreviewPhoto

    /// Callback when user wants to delete the photo
    let onDelete: () -> Void

    /// Callback to dismiss the sheet
    let onDismiss: () -> Void

    @State private var showDeleteConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                // Photo
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }

                // Blur warning overlay
                if photo.isBlurry {
                    VStack {
                        Spacer()

                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("This photo appears blurry")
                                .foregroundStyle(.white)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("Photo \(photo.index + 1)")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Delete photo")
                }
            }
            .toolbarBackground(.black.opacity(0.8), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .confirmationDialog(
            "Delete Photo?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                // Haptic feedback for destructive action
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)

                onDelete()
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This photo will be deleted and you can capture a new one.")
        }
    }
}

// MARK: - Preview Photo Model

/// Model for photo preview data
struct PreviewPhoto: Identifiable {
    let id: UUID
    let index: Int
    let image: UIImage?
    let isBlurry: Bool
}

// MARK: - Preview

#Preview("Photo Preview") {
    PhotoPreviewSheet(
        photo: PreviewPhoto(
            id: UUID(),
            index: 0,
            image: UIImage(systemName: "photo.artframe"),
            isBlurry: false
        ),
        onDelete: { print("Delete") },
        onDismiss: { print("Dismiss") }
    )
}

#Preview("Blurry Photo Preview") {
    PhotoPreviewSheet(
        photo: PreviewPhoto(
            id: UUID(),
            index: 2,
            image: UIImage(systemName: "photo.artframe"),
            isBlurry: true
        ),
        onDelete: { print("Delete") },
        onDismiss: { print("Dismiss") }
    )
}
