import SwiftUI

/// Screens 3 and 5 · Inicio (all clear / new fine).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showTipJar = false

    private var tone: HeaderTone { model.pendingFines.isEmpty ? .clear : .alert }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.homePath) {
            ScrollView {
                VStack(spacing: 24) {
                    HeaderPanel(tone: tone) {
                        if model.vehicles.isEmpty {
                            EmptyStatus()
                        } else if model.pendingFines.isEmpty {
                            ClearStatus()
                        } else {
                            AlertStatus()
                        }
                        StatusPills()
                    }
                    if let banner = model.banner {
                        BannerView(banner: banner) { model.banner = nil }
                            .padding(.horizontal, Metrics.gutter)
                    }
                    if !model.vehicles.isEmpty {
                        VehicleList()
                    }
                    HomeFooter(showTipJar: $showTipJar)
                }
                .padding(.bottom, 24)
            }
            .background(Color.sBackground)
            .navigationTitle("Home")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.checkNow() }
                    } label: {
                        if model.isChecking {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isChecking || model.vehicles.isEmpty)
                    .accessibilityLabel(Text("Check now"))
                    .accessibilityIdentifier("checkNow")
                }
            }
            .refreshable { await model.checkNow() }
            .navigationDestination(for: VehicleRoute.self) { VehicleDetailView(vehicleId: $0.id) }
            .navigationDestination(for: FineRoute.self) { FineDetailView(fineId: $0.id) }
            .sheet(isPresented: $showTipJar) { NavigationStack { TipJarView() } }
        }
    }
}

private struct EmptyStatus: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No vehicles yet")
                .font(.display(30, weight: .bold))
            Text("Tap + to add a plate and we’ll start watching it.")
                .foregroundStyle(HeaderTone.clear.inkSecondary)
        }
    }
}

private struct ClearStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.sAccentGreen)
                .frame(width: 56, height: 56)
                .sappaGlass(in: Circle())
                .accessibilityHidden(true)
            Text("All clear")
                .font(.display(30, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text("No new fines on your \(model.vehicles.count) vehicles.")
                .foregroundStyle(HeaderTone.clear.inkSecondary)
        }
    }
}

private struct AlertStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let fines = model.newFines.isEmpty ? model.pendingFines : model.newFines
        let isNew = !model.newFines.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            if isNew, let detected = fines.map(\.firstSeenAt).max() {
                Label("Detected \(Fmt.dayAndTime(detected.date))", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeaderTone.alert.inkSecondary)
            }
            Text(headline(fines: fines, isNew: isNew))
                .font(.display(28, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if let fine = model.mostUrgentFine {
                DiscountCard(fine: fine)
            }
        }
    }

    private func headline(fines: [Fine], isNew: Bool) -> String {
        let vehicleIds = Set(fines.map(\.vehicleId))
        let count = fines.count
        if vehicleIds.count == 1, let v = model.vehicle(vehicleIds.first!) {
            let name = L10n.vehicleName(v)
            return isNew ? String(localized: "\(count) new fines on \(name)")
                         : String(localized: "\(count) pending fines on \(name)")
        }
        return isNew ? String(localized: "\(count) new fines") : String(localized: "\(count) pending fines")
    }
}

struct DiscountCard: View {
    let fine: Fine
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.stageTitle(fine.discount.stage))
                    .font(.headline)
                Spacer()
                if fine.discount.stage != .full {
                    Text("ends in \(Int(fine.discount.businessDaysLeft)) business days")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if fine.discount.stage != .full {
                DiscountProgress(discount: fine.discount)
            }
            HStack(spacing: 10) {
                Button("See details") {
                    model.homePath.append(FineRoute(id: fine.id))
                }
                .buttonStyle(.sappaPrimary(.sRust))
                Link(destination: SimitLinks.payment) {
                    Label("Pay on SIMIT", systemImage: "arrow.up.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Metrics.primaryHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HeaderTone.alert.ink)
                .sappaGlass(in: Capsule(), interactive: true)
            }
        }
        .padding(16)
        .sappaGlass(in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

private struct StatusPills: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if let last = model.health?.lastOkAt {
                GlassPill(text: String(localized: "Last: \(Fmt.dayAndTime(last.date))"), systemImage: "clock")
            } else {
                GlassPill(text: String(localized: "Not checked yet"), systemImage: "clock")
            }
            GlassPill(text: String(localized: "Next: \(Fmt.time(model.nextCheck))"))
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

private struct VehicleList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Your vehicles")
            VStack(spacing: 12) {
                ForEach(model.vehicles, id: \.id) { vehicle in
                    NavigationLink(value: VehicleRoute(id: vehicle.id)) {
                        VehicleRow(vehicle: vehicle, latestNew: model.fines(for: vehicle.id).first(where: \.isNew))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle
    let latestNew: Fine?

    var body: some View {
        HStack(spacing: 14) {
            PlateChip(plate: vehicle.plate)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.vehicleName(vehicle))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sTextPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.sTextSecondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            if vehicle.newFines > 0 {
                StatusChip(kind: .new(Int(vehicle.newFines)))
            } else if vehicle.pendingFines > 0 {
                StatusChip(kind: .pending(Int(vehicle.pendingFines)))
            } else {
                StatusChip(kind: .clear)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sTextSecondary)
        }
        .padding(16)
        .frame(minHeight: 72)
        .sappaCard()
        .overlay {
            if vehicle.newFines > 0 {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .stroke(Color.sRustOutline, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if let fine = latestNew {
            return [fine.infractionCode, fine.place].compactMap { $0 }.joined(separator: " · ")
        }
        if let checked = vehicle.lastCheckedAt {
            return String(localized: "Checked \(Fmt.relative(checked.date))")
        }
        return String(localized: "Waiting for the first check")
    }
}

private struct HomeFooter: View {
    @Environment(AppModel.self) private var model
    @Binding var showTipJar: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.health?.status == .failing ? Color.sWarning : Color.sAccentGreen)
                    .frame(width: 8, height: 8)
                Text(model.health?.status == .failing
                     ? "Checks are failing · see Settings"
                     : "Automatic checks on · twice a day")
            }
            .font(.footnote)
            .foregroundStyle(Color.sTextSecondary)
            HStack(spacing: 4) {
                Text("Free forever ·")
                Button("Support the project") { showTipJar = true }
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .foregroundStyle(Color.sTextSecondary)
        }
        .padding(.horizontal, Metrics.gutter)
    }
}

struct BannerView: View {
    let banner: AppModel.Banner
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.sTextSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(Text("Close"))
        }
        .padding(.leading, 16)
        .sappaCard()
        .task {
            try? await Task.sleep(for: .seconds(6))
            onClose()
        }
    }

    private var text: String {
        switch banner {
        case .checkedNothingNew: String(localized: "Checked just now. Nothing new.")
        case .newFines(let n): String(localized: "\(n) new fines found.")
        case .skippedRecent: String(localized: "Already checked in the last 10 minutes.")
        case .failed(let e): L10n.errorClass(e)
        case .busy: String(localized: "A check is already running.")
        }
    }

    private var icon: String {
        switch banner {
        case .checkedNothingNew, .skippedRecent: "checkmark.circle.fill"
        case .newFines: "exclamationmark.circle.fill"
        case .failed, .busy: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch banner {
        case .checkedNothingNew, .skippedRecent: .sAccentGreen
        case .newFines: .sRust
        case .failed, .busy: .sWarning
        }
    }
}
