//
//  LiveChallengeViews.swift
//  Dialed
//
//  The Challenge tab's "Live" card (invite your friend / latest trash
//  talk) and the sheet behind it: server address, invite link, chat.
//

import SwiftUI

struct LiveChallengeCard: View {
    @ObservedObject var sync: ChallengeSync
    let friendName: String
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(sync.isLive ? "Live with \(friendName)" : "Make it live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Spacer()
                    if sync.isSyncing {
                        ProgressView().controlSize(.small)
                    } else if sync.isLive {
                        Text(sync.lastSync.map { "Synced \($0.formatted(.relative(presentation: .named)))" } ?? "Not synced yet")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
                if !sync.isLive {
                    Text("Send \(friendName) a link. They log weigh-ins from any phone's browser (or automatically from their scale), the scoreboard updates on both sides, and you can trash talk.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .multilineTextAlignment(.leading)
                } else if let other = sync.other {
                    friendDetails(other)
                }
                if sync.isLive, let last = sync.messages.last {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(last.role == "friend" ? Neka.lavender : Neka.orange)
                        Text(last.text)
                            .font(.system(size: 13))
                            .foregroundColor(Neka.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface.opacity(0.7)))
                }
                if let error = sync.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.rose)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nekaCard(wash: .lavender)
        }
        .buttonStyle(.dialedScale)
    }

    /// Their last weigh-in (and whether their scale sent it), pace, projection, streak, steps.
    @ViewBuilder
    private func friendDetails(_ o: ChallengeWire.OtherSide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pounds = o.lastPounds, let date = o.lastDate {
                HStack(spacing: 10) {
                    Image(systemName: o.lastFromScale ? "scalemass.fill" : "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.lavender)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Neka.surface))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%@ weighed in at %.1f lb", o.name, pounds))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(lastLine(o, date: date))
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("\(o.name) hasn't weighed in yet. Their first weigh-in starts their side of the scoreboard.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 8) {
                tile(o.weeklyLoss.map { String(format: "%@%.1f", $0 >= 0 ? "−" : "+", abs($0)) } ?? "—", "lb / week")
                tile(o.projectedLoss.map { String(format: "%@%.1f", $0 >= 0 ? "−" : "+", abs($0)) } ?? "—", "by the end")
                tile(o.streak > 0 ? "\(o.streak)🔥" : "—", "day streak")
                if let steps = o.stats?.stepsToday {
                    tile(Int(steps).formatted(), "steps today")
                }
            }
            if o.autoSync {
                Label("\(o.name)'s scale posts automatically", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.green)
            }
        }
    }

    private func lastLine(_ o: ChallengeWire.OtherSide, date: Date) -> String {
        let when = Calendar.current.isDateInToday(date) ? "Today"
            : Calendar.current.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let how = o.lastFromScale ? "from their scale" : "logged by hand"
        if let updated = o.lastUpdated, Calendar.current.isDateInToday(date) {
            return "\(when) · \(how) · \(updated.formatted(date: .omitted, time: .shortened))"
        }
        return "\(when) · \(how)"
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Neka.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface.opacity(0.7)))
    }
}

struct LiveChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync: ChallengeSync = .shared
    let challenge: WeightChallenge
    let ownerStart: Double?
    let readings: [WeightReading]

    @State private var draft = ""
    @State private var confirmDisconnect = false
    @State private var working = false

    private var ownerName: String {
        let name = (UserDefaults.standard.string(forKey: "user.firstName") ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Me" : name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sync.isLive { liveContent } else { setupContent }
                    if let error = sync.lastError {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.ink)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Neka.roseSoft))
                    }
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle(sync.isLive ? "Live challenge" : "Make it live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await sync.sync(readings: readings, force: true) }
            .refreshable { await sync.sync(readings: readings, force: true) }
        }
    }

    // MARK: - Setup

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your challenge server")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text("Deploy it once from the repo (challenge-worker/README.md: `npx wrangler deploy`), then paste the address it prints.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
            TextField("https://dialed-challenge.you.workers.dev", text: $sync.baseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
            TextField("Create key (only if you set one)", text: $sync.createKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
            Button {
                working = true
                Task {
                    await sync.create(challenge: challenge, ownerName: ownerName, ownerStart: ownerStart)
                    await sync.sync(readings: readings, force: true)
                    working = false
                }
            } label: {
                HStack {
                    if working { ProgressView().tint(Neka.onInk) }
                    Text("Create invite for \(challenge.friendDisplayName)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.nekaPrimary)
            .disabled(sync.baseURL.trimmingCharacters(in: .whitespaces).isEmpty || working)
            Text("Your weigh-ins from the challenge window upload to your server; nothing else does. \(challenge.friendDisplayName)'s weigh-ins replace the ones you typed in by hand.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Live

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let invite = sync.inviteURL {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Invite link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("Anyone with this link can post as \(challenge.friendDisplayName), so send it only to them.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                    ShareLink(item: invite,
                              message: Text("You're on. Log your weigh-ins here and watch the scoreboard: ")) {
                        Label("Send invite", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.nekaPrimary)
                    Button {
                        UIPasteboard.general.url = invite
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    }
                }
                .padding(16)
                .nekaCard(wash: .lavender)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Trash talk")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                if sync.messages.isEmpty {
                    Text("Quiet so far. Say something.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
                ForEach(sync.messages) { m in
                    let mine = m.role == "owner"
                    HStack {
                        if mine { Spacer(minLength: 40) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.text)
                                .font(.system(size: 14))
                                .foregroundColor(Neka.ink)
                            Text(mine ? "You" : challenge.friendDisplayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Neka.inkTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(mine ? Neka.orangeSoft : Neka.track))
                        if !mine { Spacer(minLength: 40) }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Say something…", text: $draft)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.track))
                    Button {
                        let text = draft
                        draft = ""
                        Task { await sync.post(text) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Neka.onInk)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Neka.ink))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send")
                }
            }
            .padding(16)
            .nekaCard()

            Button("Stop syncing on this phone", role: .destructive) { confirmDisconnect = true }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .confirmationDialog("Stop syncing?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                    Button("Stop syncing", role: .destructive) { sync.disconnect() }
                } message: {
                    Text("The scoreboard stays on your server and \(challenge.friendDisplayName)'s link keeps working; this phone just stops updating it.")
                }
        }
    }
}
