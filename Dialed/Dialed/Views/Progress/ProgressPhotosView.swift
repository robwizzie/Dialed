//
//  ProgressPhotosView.swift
//  Dialed
//
//  Weekly progress photos: take this week's shot with last week's ghost
//  over the camera, browse by week, open one to edit / retake / delete,
//  and compare any two side by side or with a before/after wipe.
//  Photos live only on this device (ProgressPhotoStore).
//

import SwiftUI
import SwiftData
import PhotosUI

struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var store = ProgressPhotoStore.shared

    /// Camera request: what to replace (retake) and what to ghost.
    private struct CaptureRequest: Identifiable {
        let id = UUID()
        let replacing: ProgressPhotoEntry?
        let ghost: UIImage?
    }

    /// A photo waiting for its date / weight / note before saving.
    struct PendingPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let replacing: ProgressPhotoEntry?
    }

    @State private var capture: CaptureRequest?
    @State private var captured: UIImage?
    @State private var pending: PendingPhoto?
    @State private var detail: ProgressPhotoEntry?
    @State private var retakeAfterDetail: ProgressPhotoEntry?
    @State private var pickerItem: PhotosPickerItem?

    private var hasThisWeek: Bool { store.index.hasPhoto(inWeekOf: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.entries.count >= 2, let first = store.index.first, let latest = store.index.latest {
                    NavigationLink {
                        ProgressCompareView(before: first, after: latest)
                    } label: {
                        compareTeaser(first: first, latest: latest)
                    }
                    .buttonStyle(.dialedScale)
                }
                if store.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(store.index.weeks()) { week in
                        weekSection(week)
                    }
                }
                Text("Photos stay on this iPhone. Dialed never uploads them.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Progress photos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $capture, onDismiss: {
            if let image = captured {
                let replacing = lastCaptureReplacing
                captured = nil
                pending = PendingPhoto(image: image, replacing: replacing)
            }
        }) { request in
            ProgressCameraView(ghost: request.ghost) { image in
                captured = image
                lastCaptureReplacing = request.replacing
            }
        }
        .sheet(item: $pending) { p in
            ProgressPhotoSaveSheet(pending: p)
        }
        .sheet(item: $detail, onDismiss: {
            if let entry = retakeAfterDetail {
                retakeAfterDetail = nil
                startCapture(replacing: entry)
            }
        }) { entry in
            ProgressPhotoDetailView(entry: entry) {
                retakeAfterDetail = entry
                detail = nil
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pending = PendingPhoto(image: image, replacing: nil)
                }
                pickerItem = nil
            }
        }
    }

    @State private var lastCaptureReplacing: ProgressPhotoEntry?

    private func startCapture(replacing: ProgressPhotoEntry?) {
        // Ghost = the photo before the one being retaken, else the latest.
        let ghostEntry = replacing.flatMap { store.index.latest(before: $0.date) } ?? (replacing == nil ? store.index.latest : nil)
        let ghost = ghostEntry.flatMap { store.image(for: $0) }
        if ProgressCameraModel.isCameraAvailable {
            capture = CaptureRequest(replacing: replacing, ghost: ghost)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NekaPill(text: hasThisWeek ? "THIS WEEK · DONE" : "THIS WEEK · NOT YET",
                         tint: hasThisWeek ? Neka.green : Neka.lavender,
                         fill: hasThisWeek ? Neka.greenSoft : Neka.lavenderSoft)
                Spacer()
                Text("\(store.entries.count) photo\(store.entries.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }
            Text("Weekly check-in")
                .font(Neka.display(26, weight: .bold))
                .foregroundColor(Neka.ink)
            Label("Same spot, same light, same pose — Sunday mornings", systemImage: "sun.horizon.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The camera shows last week's photo as a ghost with head and feet marks, so you can match it. Use the 3 s or 10 s timer and prop the phone up.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if ProgressCameraModel.isCameraAvailable {
                Button { startCapture(replacing: nil) } label: {
                    Label(hasThisWeek ? "Take another photo" : "Take this week's photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Neka.track))
            }
        }
        .padding(16)
        .nekaCard(wash: .lavender)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.stand")
                .font(.system(size: 36))
                .foregroundColor(Neka.inkTertiary)
            Text("No photos yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text("Your first photo is the \"before\". In a few weeks you'll be glad you took it.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .nekaCard()
    }

    private func compareTeaser(first: ProgressPhotoEntry, latest: ProgressPhotoEntry) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                thumb(first).frame(width: 44, height: 58).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                thumb(latest).frame(width: 44, height: 58).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare first vs latest")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(compareSubtitle(first: first, latest: latest))
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(12)
        .nekaCard()
    }

    private func compareSubtitle(first: ProgressPhotoEntry, latest: ProgressPhotoEntry) -> String {
        let days = Calendar.current.dateComponents([.day], from: first.date, to: latest.date).day ?? 0
        var text = "\(max(1, days / 7)) week\(days / 7 == 1 ? "" : "s") apart"
        if let change = ProgressPhotoIndex.weightChange(from: first, to: latest) {
            text += " · \(StrengthProgression.signed(change)) lb"
        }
        return text
    }

    // MARK: - Weeks

    private func weekSection(_ week: ProgressPhotoIndex.Week) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week of \(week.start.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Neka.inkTertiary)
                .textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(week.photos) { entry in
                    Button { detail = entry } label: { gridCell(entry) }
                        .buttonStyle(.dialedScale)
                }
            }
        }
    }

    private func gridCell(_ entry: ProgressPhotoEntry) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay { thumb(entry) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 11, weight: .bold))
                    if let w = entry.weightLbs {
                        Text("\(String(format: "%.1f", w)) lb")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func thumb(_ entry: ProgressPhotoEntry) -> some View {
        if let image = store.thumbnail(for: entry) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(Neka.track)
        }
    }
}

// MARK: - Save sheet

/// Confirm date / weight / note for a new (or retaken) photo.
struct ProgressPhotoSaveSheet: View {
    let pending: ProgressPhotosView.PendingPhoto

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var weight: Double?
    @State private var note = ""
    @State private var loadedWeight = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: pending.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .listRowBackground(Color.clear)
                }
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("lb", value: $weight, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("lb").foregroundColor(.secondary)
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text(loadedWeight && weight != nil ? "Weight is your scale reading closest to this day." : "Add your weight to see it next to the photo.")
                }
            }
            .navigationTitle(pending.replacing == nil ? "New progress photo" : "Retake photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if let r = pending.replacing {
                    date = r.date
                    note = r.note ?? ""
                    weight = r.weightLbs
                }
                if weight == nil { weight = await nearestWeight(to: date) }
                loadedWeight = true
            }
        }
    }

    private func nearestWeight(to day: Date) async -> Double? {
        let since = Calendar.current.date(byAdding: .day, value: -4, to: day) ?? day
        let readings = await WeightDataSource.readings(context: context, since: since)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day)) ?? day
        return readings.filter { $0.date < end }.max { $0.date < $1.date }?.pounds
            .map { ($0 * 10).rounded() / 10 }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        ProgressPhotoStore.shared.add(
            pending.image, date: date, weightLbs: weight,
            note: trimmed.isEmpty ? nil : trimmed, replacing: pending.replacing
        )
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

// MARK: - Detail

struct ProgressPhotoDetailView: View {
    let entry: ProgressPhotoEntry
    var onRetake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ProgressPhotoStore.shared
    @State private var weight: Double?
    @State private var note = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let image = store.image(for: entry) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Weight")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Neka.ink)
                            Spacer()
                            TextField("lb", value: $weight, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("lb")
                                .foregroundColor(Neka.inkSecondary)
                        }
                        TextField("Note", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                            .font(.system(size: 14))
                    }
                    .padding(16)
                    .nekaCard()

                    if store.entries.count >= 2 {
                        let other = entry.id == store.index.first?.id ? store.index.latest : store.index.first
                        if let other {
                            NavigationLink {
                                ProgressCompareView(
                                    before: other.date < entry.date ? other : entry,
                                    after: other.date < entry.date ? entry : other
                                )
                            } label: {
                                Label(entry.id == store.index.first?.id ? "Compare with latest" : "Compare with first", systemImage: "square.split.2x1")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.nekaPrimary)
                        }
                    }

                    HStack(spacing: 12) {
                        if ProgressCameraModel.isCameraAvailable {
                            Button { onRetake() } label: {
                                Label("Retake", systemImage: "camera.rotate")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Neka.track))
                            }
                            .foregroundColor(Neka.ink)
                        }
                        Button { confirmDelete = true } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Neka.roseSoft))
                        }
                        .foregroundColor(Neka.rose)
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        if weight != entry.weightLbs || trimmed != (entry.note ?? "") {
                            store.update(entry, weightLbs: weight, note: trimmed.isEmpty ? nil : trimmed)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) {
                    store.delete(entry)
                    dismiss()
                }
            } message: {
                Text("It's removed from this iPhone. This can't be undone.")
            }
            .onAppear {
                weight = entry.weightLbs
                note = entry.note ?? ""
            }
        }
    }
}
