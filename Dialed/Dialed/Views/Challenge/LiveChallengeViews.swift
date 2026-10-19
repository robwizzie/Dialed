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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(sync.isLive ? "Live with \(friendName)" : "Make it live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Spacer()
                    if sync.isLive {
                        Text(sync.lastSync.map { "Synced \($0.formatted(.relative(presentation: .named)))" } ?? "Not synced yet")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
                if !sync.isLive {
                    Text("Send \(friendName) a link. They log weigh-ins from any phone's browser, the scoreboard updates on both sides, and you can trash talk.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .multilineTextAlignment(.leading)
                } else if let last = sync.messages.last {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(last.role == "friend" ? Neka.lavender : Neka.orange)
                        Text(last.text)
                            .font(.system(size: 13))
                            .foregroundColor(Neka.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text("No trash talk yet. Open to start it.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
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
