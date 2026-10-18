//
//  ProfileSheet.swift
//  Dialed
//
//  Your name and photo for the Home hero. Pick a waist-up photo against
//  any background; Dialed lifts you out of it automatically. Sliders fine-
//  tune how you sit in the hero since every photo is framed differently.
//

import SwiftUI
import PhotosUI

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var photos = ProfilePhotoStore.shared

    @State private var firstName: String = UserDefaults.standard.string(forKey: "user.firstName") ?? ""
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photos.original == nil ? "Choose a photo" : "Change photo", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(.nekaPrimary)

                    if photos.original != nil {
                        framingControls
                    }

                    nameField

                    tips

                    if photos.original != nil {
                        Button(role: .destructive) {
                            photos.removePhoto()
                        } label: {
                            Text("Remove photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Neka.rose)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .nekaPageBackground()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveName()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Neka.ink)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await photos.setPhoto(data: data)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    // MARK: - Pieces

    private var preview: some View {
        HomeHeroView(
            image: photos.heroImage,
            isCutout: photos.hasCutout,
            isProcessing: photos.isProcessing,
            photoScale: photos.heroScale,
            photoOffsetY: photos.heroOffsetY,
            heartRate: 62,
            heartRateIsLive: false,
            breathingRate: 14,
            spO2: 98,
            weight: nil,
            weightNote: "Preview",
            caption: photos.hasCutout ? "Background removed ✓" : "Preview",
            onTapPhoto: {}
        )
        .padding(.top, 8)
    }

    private var framingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Framing")
                .font(Neka.label)
                .foregroundColor(Neka.ink)
            slider(title: "Size", value: $photos.heroScale, range: 0.7...1.4)
            slider(title: "Position", value: $photos.heroOffsetY, range: -120...120)
        }
        .padding(16)
        .nekaCard()
    }

    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .frame(width: 60, alignment: .leading)
            Slider(value: value, in: range)
                .tint(Neka.ink)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First name")
                .font(Neka.label)
                .foregroundColor(Neka.ink)
            TextField("Your name", text: $firstName)
                .textContentType(.givenName)
                .font(.system(size: 17))
                .foregroundColor(Neka.ink)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Neka.surface)
                )
                .onSubmit(saveName)
        }
        .padding(16)
        .nekaCard()
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Best results", systemImage: "lightbulb")
                .font(Neka.label)
                .foregroundColor(Neka.ink)
            Text("Use a waist-up photo, facing slightly to the side, in good light. Dialed removes the background on-device — your photo never leaves your phone.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .nekaCard(wash: .mint)
    }

    private func saveName() {
        UserDefaults.standard.set(firstName.trimmingCharacters(in: .whitespaces), forKey: "user.firstName")
    }
}
