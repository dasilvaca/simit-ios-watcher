import SwiftUI

/// Multas tab: every fine, pending first.
struct FinesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.finesPath) {
            List {
                let pending = model.fines.filter { $0.status != .paid }
                let paid = model.fines.filter { $0.status == .paid }
                if model.fines.isEmpty {
                    ContentUnavailableView {
                        Label("No fines", systemImage: "checkmark.seal")
                    } description: {
                        Text("When SIMIT shows a fine for one of your plates, it appears here.")
                    }
                    .listRowBackground(Color.clear)
                }
                if !pending.isEmpty {
                    Section("Pending") {
                        ForEach(pending, id: \.id) { fine in
                            NavigationLink(value: FineRoute(id: fine.id)) { FineRow(fine: fine) }
                        }
                    }
                }
                if !paid.isEmpty {
                    Section("Paid or resolved") {
                        ForEach(paid, id: \.id) { fine in
                            NavigationLink(value: FineRoute(id: fine.id)) { FineRow(fine: fine) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Fines")
            .navigationDestination(for: FineRoute.self) { FineDetailView(fineId: $0.id) }
            .refreshable { await model.checkNow() }
        }
    }
}

struct FineRow: View {
    let fine: Fine

    var body: some View {
        HStack(spacing: 12) {
            PlateChip(plate: fine.plate, size: 13)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text([fine.infractionCode, fine.place].compactMap { $0 }.joined(separator: " · "))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if fine.isNew {
                        Text("New")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.sRust))
                    }
                }
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Color.sTextSecondary)
            }
            Spacer(minLength: 4)
            Text(Fmt.cop(fine.amount))
                .font(.display(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(fine.status == .pending ? Color.sRust : Color.sTextSecondary)
        }
        .padding(.vertical, 4)
    }

    private var caption: String {
        if fine.status == .paid { return L10n.status(.paid) }
        switch fine.discount.stage {
        case .fifty, .twentyFive:
            return String(localized: "\(L10n.stageTitle(fine.discount.stage)) · \(Int(fine.discount.businessDaysLeft)) business days")
        case .full:
            return L10n.stageTitle(.full)
        }
    }
}
