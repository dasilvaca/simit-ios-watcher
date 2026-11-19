import SwiftUI

struct VehicleDetailView: View {
    let vehicleId: Int64
    @Environment(AppModel.self) private var model
    @State private var nickname = ""
    @State private var confirmRemove = false

    var body: some View {
        if let vehicle = model.vehicle(vehicleId) {
            List {
                Section {
                    HStack {
                        Spacer()
                        PlateChip(plate: vehicle.plate, size: 30)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Nickname") {
                    TextField("e.g. Main motorcycle", text: $nickname)
                        .onSubmit { model.rename(vehicle, to: nickname) }
                        .submitLabel(.done)
                    LabeledContent("Type", value: L10n.kindName(vehicle.kind))
                    LabeledContent("Last check",
                                   value: vehicle.lastCheckedAt.map { Fmt.dayAndTime($0.date) } ?? String(localized: "Not checked yet"))
                }
                Section("Fines") {
                    let fines = model.fines(for: vehicle.id)
                    if fines.isEmpty {
                        Label("No fines", systemImage: "checkmark.seal")
                            .foregroundStyle(Color.sGreenText)
                    }
                    ForEach(fines, id: \.id) { fine in
                        NavigationLink(value: FineRoute(id: fine.id)) { FineRow(fine: fine) }
                    }
                }
                Section {
                    Button("Remove vehicle", role: .destructive) { confirmRemove = true }
                }
            }
            .navigationTitle(L10n.vehicleName(vehicle))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { nickname = vehicle.nickname ?? "" }
            .onDisappear {
                if nickname != (vehicle.nickname ?? "") { model.rename(vehicle, to: nickname) }
            }
            .confirmationDialog("Remove \(vehicle.plate)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await model.remove(vehicle) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its fines and reminders are deleted from this iPhone.")
            }
        } else {
            ContentUnavailableView("Vehicle removed", systemImage: "car")
        }
    }
}
