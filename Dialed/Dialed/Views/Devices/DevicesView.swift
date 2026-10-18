//
//  DevicesView.swift
//  Dialed
//
//  Where your gear plugs in: Pixel Watch (through your Fitbit account),
//  smart scale and smart water bottle (through Apple Health or Fitbit).
//  Shows what each one last reported so you can tell at a glance whether
//  it's syncing.
//

import SwiftUI
import SwiftData

@MainActor
final class DevicesViewModel: ObservableObject {
    @Published var lastWeight: WeightReading?
    @Published var waterTodayOz: Double?
    @Published var watchSyncedAt: Date?
    @Published var isSyncing = false
    @Published var message: String?

    func refresh(context: ModelContext) async {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        lastWeight = await WeightDataSource.readings(context: context, since: since).last

        var water = (try? await HealthKitManager.shared.fetchWaterIntake(for: Date())) ?? 0
        if FitbitTokenStore.isConnected,
           let ml = try? await FitbitAPIClient.shared.water(on: Date()).summary?.water {
            water = max(water, ml / 29.5735)
        }
        waterTodayOz = water > 0 ? water : nil
    }

    func connectFitbit(context: ModelContext) async {
        do {
            try await FitbitAuthService.shared.connect()
            message = "Connected. Pulling the last two weeks…"
            await syncWatch(context: context, backfill: true)
        } catch {
            message = error.localizedDescription
        }
    }

    func syncWatch(context: ModelContext, backfill: Bool = false) async {
        isSyncing = true
        defer { isSyncing = false }
        let sync = FitbitSyncService(modelContext: context)
        if backfill {
            await sync.backfill(days: 14)
        } else {
            await sync.syncDay(Date())
        }
        try? context.save()
        if let error = sync.lastError {
            message = error
        } else {
            watchSyncedAt = sync.lastSyncedAt
            message = "Watch synced."
        }
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
    @ObservedObject private var fitbit = FitbitAuthService.shared

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
                scaleCard
                bottleCard
                healthCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .nekaPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.colorScheme, .light)
        .task { await viewModel.refresh(context: modelContext) }
    }

    // MARK: - Cards

    private var watchCard: some View {
        deviceCard(
            icon: "watch.analog",
            tint: Neka.green, fill: Neka.greenSoft,
            title: "Google Pixel Watch",
            subtitle: "Sleep, HRV, heart rate, SpO₂, breathing, steps — via your Fitbit account.",
            status: fitbit.isConnected ? "Connected" : "Not connected",
            statusOK: fitbit.isConnected,
            detail: viewModel.watchSyncedAt.map { "Synced \($0.formatted(.relative(presentation: .named)))" }
        ) {
            if fitbit.isConnected {
                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.syncWatch(context: modelContext) }
                    } label: {
                        HStack {
                            if viewModel.isSyncing { ProgressView().tint(.white) }
                            Text(viewModel.isSyncing ? "Syncing…" : "Sync now")
                        }
                    }
                    .buttonStyle(.nekaPrimary)
                    .disabled(viewModel.isSyncing)

                    Button("Disconnect") { fitbit.disconnect() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.rose)
                        .padding(.horizontal, 12)
                }
            } else if FitbitConfig.clientID == nil {
                Text("One-time setup: add your Fitbit app's Client ID to the Dialed target (see SETUP_FITBIT.md), then connect here.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("Connect Fitbit account") {
                    Task { await viewModel.connectFitbit(context: modelContext) }
                }
                .buttonStyle(.nekaPrimary)
            }
        }
    }

    private var scaleCard: some View {
        deviceCard(
            icon: "scalemass.fill",
            tint: Neka.orange, fill: Neka.orangeSoft,
            title: "Smart scale",
            subtitle: "Reads weigh-ins your scale writes to Apple Health or Fitbit. Manual weigh-ins work too.",
            status: viewModel.lastWeight.map { String(format: "%.1f lb", $0.pounds) } ?? "No readings yet",
            statusOK: viewModel.lastWeight != nil,
            detail: viewModel.lastWeight.map { "\($0.source.displayName) · \($0.date.formatted(.relative(presentation: .named)))" }
        ) { EmptyView() }
    }

    private var bottleCard: some View {
        deviceCard(
            icon: "waterbottle.fill",
            tint: Neka.sky, fill: Neka.skySoft,
            title: "Smart water bottle",
            subtitle: "HidrateSpark, Larq and others sync water to Apple Health; Dialed adds it to your day automatically.",
            status: viewModel.waterTodayOz.map { "\(Int($0)) oz today" } ?? "Nothing synced today",
            statusOK: viewModel.waterTodayOz != nil,
            detail: nil
        ) { EmptyView() }
    }

    private var healthCard: some View {
        deviceCard(
            icon: "heart.text.square.fill",
            tint: Neka.rose, fill: Neka.roseSoft,
            title: "Apple Health",
            subtitle: "The bridge for your scale, bottle, iPhone steps and food apps.",
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
