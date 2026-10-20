//
//  DevicesView.swift
//  Dialed
//
//  Where your gear plugs in: Pixel Watch (through the Google Health API —
//  the Fitbit Web API shuts down Oct 30, 2026), smart scale (Apple Health
//  or Google Health) and WaterH bottle (WaterH app → Apple Health). Shows
//  what each one last reported plus a per-metric Data check, so it's
//  obvious when something isn't syncing.
//

import SwiftUI
import SwiftData

@MainActor
final class DevicesViewModel: ObservableObject {
    @Published var lastWeight: WeightReading?
    @Published var waterTodayOz: Double?
    @Published var waterApps: [String] = []
    @Published var isSyncing = false
    @Published var message: String?

    func refresh(context: ModelContext) async {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        lastWeight = await WeightDataSource.readings(context: context, since: since).last

        let today = Calendar.current.startOfDay(for: Date())
        let water = (try? await HealthKitManager.shared.fetchWaterIntake(for: Date())) ?? 0
        waterApps = await HealthKitManager.shared.sourceNames(.dietaryWater, since: today.addingTimeInterval(-7 * 86_400))
        waterTodayOz = water > 0 ? water : nil
    }

    func connectWatch(context: ModelContext) async {
        do {
            try await GoogleHealthAuth.shared.connect()
            message = "Connected. Pulling the last two weeks from your Pixel Watch…"
            await syncWatch(context: context, days: 14)
        } catch {
            message = error.localizedDescription
        }
    }

    func syncWatch(context: ModelContext, days: Int = 2) async {
        isSyncing = true
        defer { isSyncing = false }
        let sync = GoogleHealthSyncService(modelContext: context)
        await sync.sync(days: days)
        DataDiagnostics.shared.watchError = sync.lastError
        message = sync.lastError ?? "Pixel Watch synced."
        if sync.lastError == nil {
            UserDefaults.standard.set(Date(), forKey: "home.lastGoogleHealthSync")
            UserDefaults.standard.set(true, forKey: "home.googleHealthBackfilled.v1")
        }
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
        await refresh(context: context)
    }

    func requestHealth() async {
        do {
            try await HealthKitManager.shared.requestAuthorization()
            message = "Apple Health access updated."
        } catch {
            message = error.localizedDescription
        }
    }
}

struct DevicesView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = DevicesViewModel()
    @ObservedObject private var google = GoogleHealthAuth.shared
    @ObservedObject private var diagnostics = DataDiagnostics.shared
    @AppStorage(GoogleHealthConfig.clientIDDefaultsKey) private var savedClientID = ""
    @State private var clientIDDraft = ""
    @State private var showSetupSteps = false
    /// Raw JSON of the latest Google sleep data point (diagnostic).
    @State private var rawSleep: RawSleepText?
    @State private var loadingRawSleep = false

    struct RawSleepText: Identifiable {
        let text: String
        var id: String { text }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devices")
                        .font(Neka.display(34, weight: .bold))
                        .tracking(-0.8)
                        .foregroundColor(Neka.ink)
                    Text("Everything that feeds your dashboard.")
                        .font(.system(size: 14))
                        .foregroundColor(Neka.inkSecondary)
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Neka.amberSoft))
                }

                watchCard
                bottleCard
                scaleCard
                healthCard
                intelligenceCard
                dataCheckCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .nekaPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh(context: modelContext) }
        .sheet(item: $rawSleep) { raw in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What Google sends for your latest night. Dialed reads a sleep score from sleepScore, overallScore or score (on the night or its summary) if one appears here.")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                        Text(raw.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Neka.ink)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                }
                .nekaPageBackground()
                .navigationTitle("Raw sleep data")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { rawSleep = nil } }
                    ToolbarItem(placement: .cancellationAction) {
                        ShareLink(item: raw.text) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
    }

    // MARK: - Pixel Watch (Google Health)

    private var watchCard: some View {
        deviceCard(
            icon: "watch.analog",
            tint: Neka.green, fill: Neka.greenSoft,
            title: "Google Pixel Watch",
            subtitle: "Sleep, HRV, heart rate, SpO₂, breathing and steps — through the Google Health API.",
            status: google.isConnected ? "Connected" : "Not connected",
            statusOK: google.isConnected,
            detail: (UserDefaults.standard.object(forKey: "home.lastGoogleHealthSync") as? Date)
                .map { "Synced \($0.formatted(.relative(presentation: .named)))" }
        ) {
            if google.isConnected {
                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.syncWatch(context: modelContext) }
                    } label: {
                        HStack {
                            if viewModel.isSyncing { ProgressView().tint(Neka.onInk) }
                            Text(viewModel.isSyncing ? "Syncing…" : "Sync now")
                        }
                    }
                    .buttonStyle(.nekaPrimary)
                    .disabled(viewModel.isSyncing)

                    Button("Disconnect") { google.disconnect() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.rose)
                        .padding(.horizontal, 12)
                }
                Button {
                    loadingRawSleep = true
                    Task {
                        let text = await GoogleHealthSyncService(modelContext: modelContext).rawLatestSleep()
                        loadingRawSleep = false
                        rawSleep = RawSleepText(text: text)
                    }
                } label: {
                    Label(loadingRawSleep ? "Loading…" : "Raw Google sleep data", systemImage: "curlybraces")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
                .disabled(loadingRawSleep)
            } else if GoogleHealthConfig.clientID == nil {
                clientIDSetup
            } else {
                Button("Connect with Google") {
                    Task { await viewModel.connectWatch(context: modelContext) }
                }
                .buttonStyle(.nekaPrimary)
                if !savedClientID.isEmpty {
                    Button("Change Client ID") { savedClientID = "" }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
        }
    }

    /// One-time Google Cloud setup, then paste the iOS Client ID.
    private var clientIDSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSetupSteps.toggle() }
            } label: {
                HStack {
                    Text("One-time setup (about 5 min)")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: showSetupSteps ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Neka.ink)
            }

            if showSetupSteps {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "On your phone, open the **Google Health** app (formerly Fitbit) and make sure your Pixel Watch syncs to your Google account.")
                    step(2, "Open **console.cloud.google.com** → create a project → search for **Google Health API** → Enable.")
                    step(3, "**Google Auth Platform → Audience:** External. Add your Google email under **Test users**.")
                    step(4, "**Data Access → Add scopes:** search \"Google Health\" and add the read-only activity, health metrics, sleep, nutrition and profile scopes.")
                    step(5, "**Clients → Create client → iOS**, bundle ID `org.robertwiscount.Dialed`. Copy the Client ID.")
                    step(6, "Paste it below and tap Save, then **Connect with Google**.")
                    step(7, "To stay connected past 7 days, set **Audience → Publishing status** to **In production** (personal use doesn't need verification; tap through the \"unverified app\" warning).")
                }
                Link(destination: URL(string: "https://console.cloud.google.com/apis/library/health.googleapis.com")!) {
                    Label("Open Google Cloud console", systemImage: "safari")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                }
            }

            HStack(spacing: 8) {
                TextField("….apps.googleusercontent.com", text: $clientIDDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Neka.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
                Button("Save") {
                    savedClientID = clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.onInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.ink))
                .disabled(GoogleHealthConfig.reversedClientID(clientIDDraft) == nil)
                .opacity(GoogleHealthConfig.reversedClientID(clientIDDraft) == nil ? 0.4 : 1)
            }
            if !clientIDDraft.isEmpty && GoogleHealthConfig.reversedClientID(clientIDDraft) == nil {
                Text("That doesn't look like an iOS Client ID — it should end in .apps.googleusercontent.com.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.rose)
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Neka.onInk)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Neka.ink))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - WaterH bottle

    private var bottleCard: some View {
        let fromWaterH = viewModel.waterApps.contains { $0.localizedCaseInsensitiveContains("waterh") }
        return deviceCard(
            icon: "waterbottle.fill",
            tint: Neka.sky, fill: Neka.skySoft,
            title: "WaterH bottle",
            subtitle: "The WaterH app writes your sips to Apple Health; Dialed picks them up automatically.",
            status: viewModel.waterTodayOz.map { "\(Int($0)) oz today" } ?? "Nothing synced today",
            statusOK: fromWaterH || viewModel.waterTodayOz != nil,
            detail: viewModel.waterApps.isEmpty ? nil : "From \(viewModel.waterApps.joined(separator: ", "))"
        ) {
            if !fromWaterH {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Open the **WaterH** app with your bottle paired and synced.")
                    step(2, "In WaterH's settings, turn on **Apple Health** and allow it to write **Water**.")
                    step(3, "Double-check in the **Health** app → your profile → **Apps** → WaterH → Water is on.")
                    step(4, "Allow Dialed to read Water below (Apple Health → Review access).")
                }
                Link(destination: URL(string: "x-apple-health://")!) {
                    Label("Open the Health app", systemImage: "heart.text.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                }
            }
        }
    }

    // MARK: - Scale, Health, AI

    private var scaleCard: some View {
        deviceCard(
            icon: "scalemass.fill",
            tint: Neka.orange, fill: Neka.orangeSoft,
            title: "Smart scale",
            subtitle: "Reads weigh-ins your scale writes to Apple Health or Google Health. Manual weigh-ins work too.",
            status: viewModel.lastWeight.map { String(format: "%.1f lb", $0.pounds) } ?? "No readings yet",
            statusOK: viewModel.lastWeight != nil,
            detail: viewModel.lastWeight.map { "\($0.source.displayName) · \($0.date.formatted(.relative(presentation: .named)))" }
        ) { EmptyView() }
    }

    private var healthCard: some View {
        deviceCard(
            icon: "heart.text.square.fill",
            tint: Neka.rose, fill: Neka.roseSoft,
            title: "Apple Health",
            subtitle: "The bridge for WaterH, your scale, iPhone steps and food apps.",
            status: "Permissions",
            statusOK: true,
            detail: nil
        ) {
            Button("Review Apple Health access") {
                Task { await viewModel.requestHealth() }
            }
            .buttonStyle(.nekaPrimary)
        }
    }

    private var intelligenceCard: some View {
        let availability = DialedAI.availability
        return deviceCard(
            icon: "sparkles",
            tint: Neka.lavender, fill: Neka.lavenderSoft,
            title: "Apple Intelligence",
            subtitle: "Powers your daily brief, Ask Dialed, meal estimates and trash talk — on-device and private.",
            status: availability == .available ? "Ready" : "Not available",
            statusOK: availability == .available,
            detail: nil
        ) {
            if availability != .available {
                Text(availability.explanation)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
    }

    // MARK: - Data check

    /// Per-metric: what Home found on its last refresh and where from.
    private var dataCheckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Data check")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                if let checked = diagnostics.checkedAt {
                    Text(checked.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            if let error = diagnostics.watchError {
                Label("Pixel Watch sync: \(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.rose)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if diagnostics.rows.isEmpty {
                Text("Open Home once to run a check.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
            ForEach(diagnostics.rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.isFound ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 14))
                        .foregroundColor(row.isFound ? Neka.green : Neka.inkTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.metric)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(row.isFound ? (row.source ?? "—") : "Nothing found yet")
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.value ?? "--")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        if let date = row.date {
                            Text(date.formatted(.relative(presentation: .named)))
                                .font(.system(size: 10))
                                .foregroundColor(Neka.inkTertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Card shell

    private func deviceCard<Actions: View>(
        icon: String,
        tint: Color,
        fill: Color,
        title: String,
        subtitle: String,
        status: String,
        statusOK: Bool,
        detail: String?,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                NekaIconBadge(systemName: icon, tint: tint, fill: fill, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Neka.title)
                        .foregroundColor(Neka.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(statusOK ? Neka.green : Neka.inkTertiary)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                        .lineLimit(1)
                }
            }
            actions()
        }
        .padding(16)
        .nekaCard()
    }
}
