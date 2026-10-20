//
//  AvatarSheet.swift
//  Dialed
//
//  Your avatar, today's mood and what would move it up, the four mood
//  looks, and "future you" on your goal day. Tap any look to redo it or
//  draw it from a different photo.
//

import SwiftUI
import PhotosUI

struct AvatarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var studio = AvatarStudio.shared
    @ObservedObject private var photos = ProfilePhotoStore.shared
    @AppStorage("avatar.useOnHome") private var useOnHome = true

    let reading: AvatarMood.Reading
    let projection: WeightChallengeEngine.Projection?
    var onGoalChanged: () -> Void = {}

    @State private var hasEvent: Bool
    @State private var eventName: String
    @State private var eventDate: Date

    /// Which look the photo picker is choosing a reference for.
    private enum PickTarget: Equatable { case look(String), all }
    @State private var pickTarget: PickTarget?
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?

    init(reading: AvatarMood.Reading, projection: WeightChallengeEngine.Projection?, onGoalChanged: @escaping () -> Void = {}) {
        self.reading = reading
        self.projection = projection
        self.onGoalChanged = onGoalChanged
        let event = GoalEvent.load()
        _hasEvent = State(initialValue: event != nil)
        _eventName = State(initialValue: event?.name ?? "Brother's wedding")
        let defaultDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19)) ?? Date()
        _eventDate = State(initialValue: event?.date ?? max(defaultDate, Date()))
    }

    private var mood: AvatarMood { reading.mood }
    private var accent: Color { Color(hex: mood.accentHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let error = studio.lastError {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.ink)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Neka.amberSoft))
                    }
                    boostsCard
                    breakdownCard
                    moodsCard
                    futureCard
                    Toggle("Show my avatar on Home", isOn: $useOnHome)
                        .tint(Neka.green)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Neka.ink)
                        .padding(16)
                        .nekaCard()
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle("Your avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveGoal()
                        dismiss()
                    }
                    .foregroundColor(Neka.ink)
                }
            }
            .avatarPlaygroundSheet()
            .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item, let target = pickTarget else { return }
                pickerItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    switch target {
                    case .look(let key): await studio.setReference(data, for: key)
                    case .all:           await studio.setReference(data, for: nil)
                    }
                }
            }
        }
    }

    // MARK: - Look actions

    private func pick(_ target: PickTarget) {
        if target == .look(AvatarStudio.futureKey) { saveGoal() }
        pickTarget = target
        showPicker = true
    }

    private func redo(_ key: String) {
        if key == AvatarStudio.futureKey { saveGoal() }
        Task { await studio.regenerate(key: key) }
    }

    /// Redo / different photo / back to profile photo / remove.
    @ViewBuilder
    private func lookMenu(_ key: String) -> some View {
        if studio.canGenerate {
            Button { redo(key) } label: {
                Label(studio.images[key] == nil ? "Create this look" : "Redo this look", systemImage: "wand.and.sparkles")
            }
            .disabled(studio.referencePhoto(for: key) == nil || studio.inProgress.contains(key))
        }
        Button { pick(.look(key)) } label: {
            Label("Use a different photo…", systemImage: "photo.on.rectangle")
        }
        if studio.hasCustomReference(key) {
            Button { Task { await studio.clearReference(for: key) } } label: {
                Label("Back to my profile photo", systemImage: "person.crop.circle")
            }
        }
        if studio.images[key] != nil {
            Divider()
            Button(role: .destructive) { studio.removeImage(key) } label: {
                Label("Remove this look", systemImage: "trash")
            }
        }
    }

    /// Small round thumbnail of a look's own reference photo, if it has one.
    @ViewBuilder
    private func referenceBadge(_ key: String, size: CGFloat = 28) -> some View {
        if let ref = studio.references[key] {
            Image(uiImage: ref)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Neka.surface, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .accessibilityLabel("Uses its own photo")
        }
    }

    private var menuDot: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Neka.ink)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Neka.surface.opacity(0.9)))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(colors: [accent, accent.opacity(0.3), accent], center: .center),
                        lineWidth: 5
                    )
                    .frame(width: 214, height: 214)
                Group {
                    if let avatar = studio.image(for: mood) {
                        FocusedImage(image: avatar)
                    } else if let photo = photos.heroImage {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 80))
                            .foregroundColor(Neka.inkTertiary)
                    }
                }
                .frame(width: 196, height: 196)
                .background(Neka.surface)
                .clipShape(Circle())
                if studio.inProgress.contains(mood.rawValue) {
                    ProgressView()
                        .tint(Neka.ink)
                        .padding(14)
                        .background(Circle().fill(Neka.surface))
                }
                Text("\(reading.score)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Neka.onInk)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(accent))
                    .overlay(Circle().stroke(Neka.surface, lineWidth: 3))
                    .offset(x: 76, y: 76)
                referenceBadge(mood.rawValue, size: 40)
                    .offset(x: -76, y: 76)
            }
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text("\(mood.emoji) \(mood.title)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Neka.ink)
                Text(mood.tagline)
                    .font(.system(size: 14))
                    .foregroundColor(Neka.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            if studio.image(for: mood) != nil {
                HStack(spacing: 10) {
                    if studio.canGenerate {
                        Button { redo(mood.rawValue) } label: {
                            Label("Redo", systemImage: "wand.and.sparkles")
                        }
                        .disabled(studio.inProgress.contains(mood.rawValue))
                    }
                    Button { pick(.look(mood.rawValue)) } label: {
                        Label("Different photo", systemImage: "photo.on.rectangle")
                    }
                }
                .buttonStyle(AvatarChipButtonStyle())
            } else {
                if studio.canGenerate {
                    Button {
                        Task { await studio.generate(mood: mood) }
                    } label: {
                        Label(studio.isEnabled ? "Create this look" : "Create my avatar", systemImage: "wand.and.sparkles")
                    }
                    .buttonStyle(.nekaPrimary)
                    .disabled(studio.referencePhoto(for: mood.rawValue) == nil || studio.inProgress.contains(mood.rawValue))
                    Button { pick(.look(mood.rawValue)) } label: {
                        Text("Use a different photo for this look")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    }
                    if studio.referencePhoto(for: mood.rawValue) == nil {
                        Text("Add a photo of yourself first — tap your picture on Home.")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                } else {
                    Text("Illustrated avatars use Image Playground (Apple Intelligence). Until then, your photo stands in.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Boosts & breakdown

    private var boostsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reading.boosts.isEmpty ? "Nothing holding you back" : "What would move you up")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            if reading.boosts.isEmpty {
                Text("Every part of today is on pace. Keep it rolling.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }
            ForEach(reading.boosts, id: \.name) { boost in
                HStack(spacing: 12) {
                    Text("+\(Int(boost.gap.rounded()))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(accent.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boost.action)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(boost.name)
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today so far")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            ForEach(reading.components, id: \.name) { part in
                VStack(spacing: 5) {
                    HStack {
                        Text(part.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                        Spacer()
                        Text("\(Int(part.points.rounded())) / \(Int(part.maxPoints))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    }
                    NekaProgressBar(progress: part.points / part.maxPoints, tint: accent, height: 6)
                }
            }
            Text("Paced to the time of day — at 10 AM you only need about a fifth of each target.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Moods

    private var moodsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your four moods")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(AvatarMood.allCases) { m in
                    moodTile(m)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Tap a look to redo it or draw it from a different photo.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                Spacer(minLength: 8)
                Button { pick(.all) } label: {
                    Text("New photo for all")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func moodTile(_ m: AvatarMood) -> some View {
        let tint = Color(hex: m.accentHex)
        return VStack(spacing: 8) {
            Menu {
                lookMenu(m.rawValue)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.12))
                    if let image = studio.image(for: m) {
                        FocusedImage(image: image)
                    } else if studio.inProgress.contains(m.rawValue) {
                        ProgressView().tint(tint)
                    } else if studio.canGenerate && studio.referencePhoto(for: m.rawValue) != nil {
                        Label("Create", systemImage: "wand.and.sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tint)
                    } else {
                        Text(m.emoji).font(.system(size: 40))
                    }
                }
                .frame(height: 140)
                .overlay(alignment: .topTrailing) { menuDot.padding(8) }
                .overlay(alignment: .bottomLeading) { referenceBadge(m.rawValue).padding(8) }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(m == mood ? tint : Color.clear, lineWidth: 2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityLabel("\(m.title) look. Options.")
            Text("\(m.emoji) \(m.title)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Future you

    private var futureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Future you")
                .font(Neka.title)
                .foregroundColor(Neka.ink)

            Toggle("I'm working toward a day", isOn: $hasEvent)
                .tint(Neka.green)
                .font(.system(size: 14))
                .foregroundColor(Neka.ink)
            if hasEvent {
                TextField("What's the day?", text: $eventName)
                    .font(.system(size: 15))
                    .foregroundColor(Neka.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
                DatePicker("Date", selection: $eventDate, in: Date()..., displayedComponents: .date)
                    .font(.system(size: 14))
                    .foregroundColor(Neka.ink)
            }

            HStack(alignment: .top, spacing: 14) {
                Menu {
                    lookMenu(AvatarStudio.futureKey)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Neka.lavenderSoft)
                        if let image = studio.futureImage {
                            FocusedImage(image: image)
                        } else if studio.inProgress.contains(AvatarStudio.futureKey) {
                            ProgressView().tint(Neka.lavender)
                        } else {
                            Image(systemName: "tshirt.fill").font(.system(size: 30)).foregroundColor(Neka.lavender)
                        }
                    }
                    .frame(width: 110, height: 110)
                    .overlay(alignment: .topTrailing) { menuDot.padding(6) }
                    .overlay(alignment: .bottomLeading) { referenceBadge(AvatarStudio.futureKey, size: 24).padding(6) }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityLabel("Future you look. Options.")

                VStack(alignment: .leading, spacing: 6) {
                    if let p = projection {
                        Text(String(format: "%.1f lb", p.weight))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(String(format: "%@%.1f lb from today · %.1f lb/week trend", p.change <= 0 ? "−" : "+", abs(p.change), abs(p.weeklyRate)))
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(p.weeklyRate < -0.3 ? "Keep this pace and that's you walking in." : "Pick the pace up — a 500 calories/day deficit is about 1 lb a week.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Weigh in on a few mornings and your goal-day projection shows up here.")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if studio.canGenerate && studio.referencePhoto(for: AvatarStudio.futureKey) != nil {
                        Button {
                            saveGoal()
                            Task { await studio.generateFuture(event: hasEvent ? GoalEvent(name: eventName, date: eventDate) : nil) }
                        } label: {
                            Label(studio.futureImage == nil ? "Create the look" : "Redo the look", systemImage: "wand.and.sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Neka.ink)
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(16)
        .nekaCard(wash: .lavender)
    }

    private func saveGoal() {
        let trimmed = eventName.trimmingCharacters(in: .whitespaces)
        if hasEvent && !trimmed.isEmpty {
            GoalEvent(name: trimmed, date: Calendar.current.startOfDay(for: eventDate)).save()
        } else if !hasEvent {
            GoalEvent.clear()
        }
        onGoalChanged()
    }
}

/// Small outlined capsule button for the avatar's quick actions.
private struct AvatarChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Neka.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Neka.surface))
            .overlay(Capsule().stroke(Neka.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
