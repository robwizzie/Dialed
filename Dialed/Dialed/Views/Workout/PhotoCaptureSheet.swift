//
//  PhotoCaptureSheet.swift
//  Dialed
//
//  Photo capture interface for workout progress photos
//

import SwiftUI
import PhotosUI
import SwiftData

struct PhotoCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let workoutLog: WorkoutLog
    let onPhotoAdded: () -> Void

    @State private var selectedImage: UIImage?
    @State private var photoNotes: String = ""
    @State private var showImagePicker = false
    @State private var imageSourceType: ImageSourceType = .camera

    enum ImageSourceType {
        case camera
        case photoLibrary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Image preview or placeholder
                    if let image = selectedImage {
                        // Selected image preview
                        VStack(spacing: 12) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )

                            Button(action: {
                                selectedImage = nil
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle")
                                    Text("Remove Photo")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.red)
                            }
                        }
                    } else {
                        // Placeholder
                        VStack(spacing: 20) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary.opacity(0.3))

                            Text("Add Progress Photo")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Document your fitness journey")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            // Photo source buttons
                            HStack(spacing: 16) {
                                Button(action: {
                                    imageSourceType = .camera
                                    showImagePicker = true
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "camera")
                                            .font(.title2)
                                        Text("Camera")
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(.blue.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                .foregroundColor(.blue)

                                Button(action: {
                                    imageSourceType = .photoLibrary
                                    showImagePicker = true
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.title2)
                                        Text("Library")
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(.blue.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                .foregroundColor(.blue)
                            }
                        }
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                )
                        )
                    }

                    // Notes (optional)
                    if selectedImage != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notes (Optional)")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            TextField("How are you feeling?", text: $photoNotes, axis: .vertical)
                                .lineLimit(2...4)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                        )
                                )
                        }
                    }

                    // Tips section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                            Text("Photo Tips")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(icon: "sun.max", text: "Use good lighting for best results")
                            TipRow(icon: "person.fill", text: "Take photos in the same spot for consistency")
                            TipRow(icon: "calendar", text: "Regular photos help track progress")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.yellow.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.yellow.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePhoto()
                    }
                    .disabled(selectedImage == nil)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(
                    selectedImage: $selectedImage,
                    sourceType: imageSourceType == .camera ? .camera : .photoLibrary
                )
            }
        }
        .presentationDetents([.large])
    }

    private func savePhoto() {
        guard let image = selectedImage else { return }

        // Save image to documents directory
        guard let filename = PhotoManager.shared.savePhoto(image) else {
            print("Failed to save photo")
            return
        }

        // Create WorkoutPhoto model
        let workoutPhoto = WorkoutPhoto(
            filename: filename,
            notes: photoNotes.isEmpty ? nil : photoNotes
        )
        workoutPhoto.workoutLog = workoutLog

        modelContext.insert(workoutPhoto)
        try? modelContext.save()

        onPhotoAdded()
        dismiss()
    }
}

// MARK: - Tip Row

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Image Picker (UIKit Bridge)

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    @Previewable @State var workoutLog = WorkoutLog(
        dayDate: Date(),
        tag: .push,
        workoutScore: 4
    )
    PhotoCaptureSheet(workoutLog: workoutLog, onPhotoAdded: {})
}
