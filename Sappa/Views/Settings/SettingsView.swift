import StoreKit
import SwiftUI
import UserNotifications

/// Screen 4 · Ajustes.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.Key.morningMinutes, store: Prefs.store) private var morning = 6 * 60
    @AppStorage(Prefs.Key.eveningMinutes, store: Prefs.store) private var evening = 18 * 60
    @AppStorage(Prefs.Key.notifyNewFine, store: Prefs.store) private var notifyNewFine = true
    @AppStorage(Prefs.Key.notifyDiscount, store: Prefs.store) private var notifyDiscount = true
    @AppStorage(Prefs.Key.notifyFailing, store: Prefs.store) private var notifyFailing = true
    @State private var confirmDelete = false
    @State private var showTipJar = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HealthCard(health: model.health)
                }

                Section("Schedule") {
                    TimeRow(title: "Morning", minutes: $morning)
                    TimeRow(title: "Evening", minutes: $evening)
                }

                Section("Alerts") {
                    ToggleRow(title: "New fine", subtitle: "Urgent, with sound", isOn: $notifyNewFine)
                    ToggleRow(title: "Discount about to end", subtitle: "1 business day before", isOn: $notifyDiscount)
                    ToggleRow(title: "If checks fail", subtitle: "After 24 h without reaching SIMIT", isOn: $notifyFailing)
                }
                .onChange(of: notifyFailing) { _, on in
                    Task {
                        if on { await model.service.notifier.rearmDeadMan() }
                        else { UNUserNotificationCenterBridge.removeDeadMan() }
                    }
                }

                Section {
                    Button { showTipJar = true } label: {
                        Label("Support the project", systemImage: "heart")
                    }
                    ShareLink(item: Diagnostics.temporaryFile(
                        named: "sappa-report.txt", contents: Diagnostics.report(core: model.core))) {
                        Label("Send report", systemImage: "exclamationmark.bubble")
                    }
                    ShareLink(item: Diagnostics.temporaryFile(
                        named: "sappa-data.json",
                        contents: (try? model.core.exportData(now: Date().unix)) ?? "{}")) {
                        Label("Export my data", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete all my data", systemImage: "trash")
                            .foregroundStyle(Color.sRust)
                    }
                    .accessibilityIdentifier("deleteAll")
                }

                Section {
                    NotAffiliatedNote()
                    LabeledContent("Version", value: "\(CoreHost.appVersion) · core \(coreVersion())")
                        .font(.footnote)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .sheet(isPresented: $showTipJar) { NavigationStack { TipJarView() } }
            .confirmationDialog("Delete all your data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { model.deleteAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your plates, fines and check history are removed from this iPhone. This can’t be undone.")
            }
        }
    }
}

enum UNUserNotificationCenterBridge {
    static func removeDeadMan() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Notifier.deadManIdentifier])
    }
}

private struct HealthCard: View {
    let health: Health?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(dotColor).frame(width: 10, height: 10)
                Text(statusText).font(.headline)
                Spacer()
                NavigationLink("See log") { RunLogView() }
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
            }
            HealthBar(runs: health?.runs ?? [])
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color.sTextSecondary)
        }
        .padding(.vertical, 6)
    }

    private var dotColor: Color {
        switch health?.status {
        case .good?: .sAccentGreen
        case .degraded?: .sWarning
        case .failing?: .sRust
        default: .sSeparator
        }
    }

    private var statusText: String {
        switch health?.status {
        case .good?: String(localized: "Working well")
        case .degraded?: String(localized: "Last check failed, retrying")
        case .failing?: String(localized: "Checks are failing")
        default: String(localized: "No checks yet")
        }
    }

    private var caption: String {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400).unix
        let week = (health?.runs ?? []).filter { $0.startedAt >= weekAgo }
        guard !week.isEmpty else { return String(localized: "Checks appear here after the first run.") }
        let ok = week.filter { $0.result == .ok }.count
        let offline = week.filter { $0.result == .offline }.count
        let failed = week.filter { $0.result == .error || $0.result == .blocked }.count
        return String(localized: "Last 7 days · \(ok) ok · \(offline) offline · \(failed) failed")
    }
}

private struct TimeRow: View {
    let title: LocalizedStringKey
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title,
                   selection: Binding(get: { CheckSchedule.dateFor(minutes: minutes) },
                                      set: {
                                          minutes = CheckSchedule.minutes(of: $0)
                                          BackgroundScheduler.scheduleNext()
                                      }),
                   displayedComponents: .hourAndMinute)
    }
}

private struct ToggleRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.footnote).foregroundStyle(Color.sTextSecondary)
            }
        }
        .tint(.sAccentGreen)
    }
}

struct RunLogView: View {
    @Environment(AppModel.self) private var model
    @State private var runs: [RunSummary] = []

    var body: some View {
        List(runs, id: \.id) { run in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Fmt.dayAndTime(run.startedAt.date)).font(.body.weight(.semibold))
                    Spacer()
                    Text(L10n.runResult(run.result))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color(run.result))
                }
                HStack(spacing: 6) {
                    Text(L10n.trigger(run.trigger))
                    Text("·")
                    Text("\(Int(run.platesChecked)) plates checked")
                    if run.platesRemaining > 0 {
                        Text("·")
                        Text("\(Int(run.platesRemaining)) pending")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.sTextSecondary)
                if let error = run.error {
                    Text(L10n.errorClass(error)).font(.footnote).foregroundStyle(Color.sRust)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .overlay {
            if runs.isEmpty { ContentUnavailableView("No checks yet", systemImage: "clock") }
        }
        .navigationTitle("Check log")
        .task { runs = (try? model.core.health(now: Date().unix, limit: 60).runs) ?? [] }
    }

    private func color(_ r: RunResult?) -> Color {
        switch r {
        case .ok?: .sGreenText
        case .offline?: .sWarning
        case .blocked?, .error?: .sRust
        case nil: .sTextSecondary
        }
    }
}

struct TipJarView: View {
    @State private var jar = TipJar()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "heart.fill").font(.largeTitle).foregroundStyle(Color.sRust)
                    Text("SAPPA is free, with no ads and no tracking. If it helps you, you can leave a tip to keep it going.")
                }
                .padding(.vertical, 6)
            }
            Section {
                switch jar.state {
                case .loading:
                    ProgressView()
                case .unavailable:
                    Text("Tips aren’t available right now.").foregroundStyle(Color.sTextSecondary)
                case .thanks:
                    Label("Thank you!", systemImage: "hands.clap.fill").foregroundStyle(Color.sGreenText)
                case .failed:
                    Text("The purchase didn’t go through.").foregroundStyle(Color.sRust)
                case .ready, .purchasing:
                    ForEach(jar.products, id: \.id) { product in
                        Button { Task { await jar.buy(product) } } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer()
                                Text(product.displayPrice).fontWeight(.semibold)
                            }
                        }
                        .disabled(jar.state == .purchasing)
                    }
                }
            }
        }
        .navigationTitle("Support the project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { await jar.load() }
    }
}
