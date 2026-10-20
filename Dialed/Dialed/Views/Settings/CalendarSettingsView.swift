//
//  CalendarSettingsView.swift
//  Dialed
//
//  Connect your calendars (Apple, and Google either through iOS or
//  directly), choose which ones count, say which mean work, and set how
//  long mornings take — everything the wake-up suggestions use.
//

import SwiftUI

struct CalendarSettingsView: View {
    @ObservedObject private var service = CalendarService.shared
    @ObservedObject private var google = GoogleCalendarAuth.shared
    @State private var prefs = CalendarPrefs.load()
    @State private var connecting = false
    @State private var error: String?
    @State private var newWorkWord = ""

    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        Form {
            Section {
                connectionRow(title: "Apple Calendar", detail: service.appleAccess ? "Connected" : "Includes Google and Outlook accounts added in iOS",
                              symbol: "calendar", connected: service.appleAccess) {
                    Task { await service.requestAppleAccess() }
                }
                connectionRow(title: "Google Calendar", detail: google.isConnected ? "Connected directly" : "Optional — sign in with Google",
                              symbol: "g.circle.fill", connected: google.isConnected) {
                    Task { await connectGoogle() }
                }
                if google.isConnected {
                    Button("Disconnect Google Calendar", role: .destructive) {
                        google.disconnect()
                        Task { await service.refresh(force: true) }
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Connect")
            } footer: {
                Text("Easiest way to bring in Google Calendar: iPhone Settings › Apps › Calendar › Calendar Accounts › Add Account › Google, then connect Apple Calendar here. Events in both show once.")
            }

            if !service.calendars.isEmpty {
                Section {
                    ForEach(service.calendars) { cal in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: cal.colorHex ?? "#8E8E93"))
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cal.title)
                                Text(cal.account)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                toggleWork(cal.id)
                            } label: {
                                Text("Work")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(prefs.workCalendarIDs.contains(cal.id) ? Neka.orangeSoft : Neka.track))
                                    .foregroundStyle(prefs.workCalendarIDs.contains(cal.id) ? Neka.orangeText : Neka.inkTertiary)
                            }
                            .buttonStyle(.borderless)
                            Toggle("", isOn: Binding(
                                get: { prefs.includes(cal.id) },
                                set: { setIncluded(cal.id, $0) }
                            ))
                            .labelsHidden()
                            .tint(Neka.green)
                        }
                    }
                } header: {
                    Text("Calendars")
                } footer: {
                    Text("Switch off calendars that shouldn't move your wake-up (birthdays, a partner's shared calendar). Tag the ones that are work.")
                }
            }

            Section {
                ForEach(weekdays, id: \.self) { wd in
                    Toggle(Calendar.current.weekdaySymbols[wd - 1], isOn: Binding(
                        get: { prefs.workDays.contains(wd) },
                        set: { on in if on { prefs.workDays.insert(wd) } else { prefs.workDays.remove(wd) } }
                    ))
                    .tint(Neka.green)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event names that mean work")
                        .font(.subheadline)
                    FlowChips(words: prefs.workKeywords) { word in
                        prefs.workKeywords.removeAll { $0 == word }
                    }
                    HStack {
                        TextField("Add a word (e.g. shift)", text: $newWorkWord)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addWorkWord)
                        Button("Add", action: addWorkWord)
                            .disabled(newWorkWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Work")
            } footer: {
                Text("A usual workday with nothing from work on your calendar, or an all-day “PTO”, “Vacation” or holiday, reads as a day off. Dialed only uses the “nothing from work” rule once your calendar shows work on at least 3 days.")
            }

            Section {
                Stepper("Get ready: \(prefs.prepMinutes) min", value: $prefs.prepMinutes, in: 15...180, step: 5)
                Stepper("Commute: \(prefs.commuteMinutes) min", value: $prefs.commuteMinutes, in: 0...120, step: 5)
                Stepper("Sleep in on days off: up to \(prefs.sleepInMinutes) min", value: $prefs.sleepInMinutes, in: 0...180, step: 15)
                Toggle("8 PM heads-up for tomorrow", isOn: $prefs.eveningReminder)
                    .tint(Neka.green)
            } header: {
                Text("Mornings")
            } footer: {
                Text("Something before noon moves your wake-up early enough to get ready and get there. Suggestions never change your alarm until you accept them.")
            }
        }
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: prefs) { _, p in
            p.save()
            Task { await WakeSuggestionStore.scheduleEveningReminder() }
        }
        .task { await service.refresh() }
    }

    private func connectionRow(title: String, detail: String, symbol: String, connected: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(connected ? Neka.greenText : Neka.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(connected ? Neka.greenSoft : Neka.track))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if connected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Neka.green)
            } else {
                Button(connecting ? "…" : "Connect", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Neka.ink)
                    .controlSize(.small)
                    .disabled(connecting)
            }
        }
    }

    private func connectGoogle() async {
        connecting = true
        defer { connecting = false }
        error = nil
        do {
            try await google.connect()
            await service.refresh(force: true)
        } catch GoogleHealthAuth.AuthError.notConfigured {
            error = "Add your Google OAuth client ID in Devices › Pixel Watch first (the same one Google Health uses)."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleWork(_ id: String) {
        if prefs.workCalendarIDs.contains(id) { prefs.workCalendarIDs.remove(id) } else { prefs.workCalendarIDs.insert(id) }
    }

    private func setIncluded(_ id: String, _ on: Bool) {
        var set = prefs.enabledCalendarIDs ?? Set(service.calendars.map(\.id))
        if on { set.insert(id) } else { set.remove(id) }
        prefs.enabledCalendarIDs = set
    }

    private func addWorkWord() {
        let word = newWorkWord.trimmingCharacters(in: .whitespaces).lowercased()
        guard !word.isEmpty, !prefs.workKeywords.contains(word) else { return }
        prefs.workKeywords.append(word)
        newWorkWord = ""
    }
}

/// Removable word chips that wrap.
private struct FlowChips: View {
    let words: [String]
    var onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(words, id: \.self) { word in
                Button { onRemove(word) } label: {
                    HStack(spacing: 4) {
                        Text(word).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Neka.track))
                    .foregroundStyle(Neka.ink)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
