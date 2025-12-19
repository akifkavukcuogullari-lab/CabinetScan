import SwiftUI
import AVFoundation

struct VisualizationPhotoView: View {
    @EnvironmentObject var appState: AppState
    let onPhotoTaken: (UIImage) -> Void
    let onSkip: () -> Void

    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var showRetakeOption = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if let image = capturedImage {
                    // Show captured photo with retake option
                    VStack(spacing: 24) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 8)

                        Text("Photo captured!")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("This photo will help visualize your new cabinets")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer()

                        VStack(spacing: 12) {
                            Button {
                                onPhotoTaken(image)
                            } label: {
                                Label("Use This Photo", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Button {
                                capturedImage = nil
                                showCamera = true
                            } label: {
                                Label("Retake Photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                } else {
                    // Instructions before taking photo
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    VStack(spacing: 12) {
                        Text("One More Step")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Stand in a corner of your kitchen and take a wide-angle photo for visualization")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        InstructionRow(icon: "arrow.up.left.and.arrow.down.right", text: "Use wide-angle if available")
                        InstructionRow(icon: "lightbulb", text: "Ensure good lighting")
                        InstructionRow(icon: "rectangle.portrait.inset.filled", text: "Capture the full kitchen view")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            onSkip()
                        } label: {
                            Text("Skip for now")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Visualization Photo")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(capturedImage: $capturedImage)
            }
        }
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    VisualizationPhotoView(
        onPhotoTaken: { _ in },
        onSkip: { }
    )
    .environmentObject(AppState.shared)
}
