import SwiftUI
import UserNotifications

/// Screen 2 · Permisos y horario.
struct PermissionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var refreshStatus: UIBackgroundRefreshStatus = .available
    @AppStorage(Prefs.Key.morningMinutes, store: Prefs.store) private var morning = 6 * 60
    @AppStorage(Prefs.Key.eveningMinutes, store: Prefs.store) private var evening = 18 * 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderPanel(tone: .clear) {
                    StepIndicator(step: 2, of: 2)
                    Text("Let it work on its own")
                        .font(.largeTitle.bold())
                    Text("We check SIMIT twice a day in the background. If there’s nothing new, we won’t bother you.")
                        .foregroundStyle(HeaderTone.clear.inkSecondary)

                    VStack(spacing: 0) {
                        PermissionRow(icon: "bell.fill", tint: .sRust,
                                      title: "Notifications",
                                      subtitle: "Only new fines and discounts about to expire") {
                            notificationAccessory
                        }
                        Divider().padding(.leading, 62)
                        PermissionRow(icon: "arrow.clockwise", tint: .sAccentGreen,
                                      title: "Background refresh",
                                      subtitle: refreshStatus == .available ? "On in iPhone Settings" : "Off in iPhone Settings") {
                            if refreshStatus == .available {
                                Label("Ready", systemImage: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.sGreenText)
                            } else {
                                Button("Settings") { openSettings() }
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .sappaGlass(in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Check schedule")
                    HStack(spacing: 12) {
                        ScheduleCard(title: "Morning", minutes: $morning)
                        ScheduleCard(title: "Evening", minutes: $evening)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    Text("iOS picks the exact minute to save battery, so it may shift a little. You can always check by hand.")
                        .font(.footnote)
                        .foregroundStyle(Color.sTextSecondary)
                        .padding(.horizontal, Metrics.gutter)
                }
            }
        }
        .background(Color.sBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button("Start watching") { finish(startNow: true) }
                    .buttonStyle(.sappaPrimary)
                    .accessibilityIdentifier("startWatching")
                Button("Not now") { finish(startNow: false) }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
            .background(Color.sBackground.opacity(0.92))
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await refreshStatuses() }
    }

    @ViewBuilder private var notificationAccessory: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Allowed", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sGreenText)
        case .denied:
            Button("Settings") { openSettings() }
                .buttonStyle(.glass)
        default:
            Button("Allow") { Task { await requestNotifications() } }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("allowNotifications")
        }
    }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatuses()
    }

    private func refreshStatuses() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        refreshStatus = UIApplication.shared.backgroundRefreshStatus
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func finish(startNow: Bool) {
        model.onboardingDone = true
        BackgroundScheduler.scheduleNext()
        if startNow {
            Task { await model.checkNow() }
        }
    }
}

struct PermissionRow<Accessory: View>: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(HeaderTone.clear.inkSecondary)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// White card with a time; tap to edit.
struct ScheduleCard: View {
    let title: LocalizedStringKey
    @Binding var minutes: Int
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.sTextSecondary)
                Text(Fmt.time(CheckSchedule.dateFor(minutes: minutes)))
                    .font(.display(24, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Color.sTextPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .sappaCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            TimeEditor(title: title, minutes: $minutes)
                .presentationDetents([.height(320)])
        }
    }
}

struct TimeEditor: View {
    let title: LocalizedStringKey
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(title,
                       selection: Binding(get: { CheckSchedule.dateFor(minutes: minutes) },
                                          set: { minutes = CheckSchedule.minutes(of: $0) }),
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            BackgroundScheduler.scheduleNext()
                            dismiss()
                        }
                    }
                }
        }
    }
}
