import SwiftUI

/// Screen 6 · Detalle del comparendo.
struct FineDetailView: View {
    let fineId: Int64
    @Environment(AppModel.self) private var model
    @State private var confirmPaid = false
    @State private var reminderSet = false

    var body: some View {
        if let fine = model.fine(fineId) {
            content(fine)
        } else {
            ContentUnavailableView("This fine is no longer on your list", systemImage: "doc.text")
        }
    }

    private func content(_ fine: Fine) -> some View {
        let tone: HeaderTone = fine.status == .pending ? .alert : .clear
        let vehicle = model.vehicle(fine.vehicleId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderPanel(tone: tone) {
                    HStack(spacing: 10) {
                        PlateChip(plate: fine.plate)
                        if let vehicle { Text(L10n.vehicleName(vehicle)).font(.subheadline.weight(.semibold)) }
                    }
                    Text(title(fine))
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Fmt.cop(fine.amount))
                        .font(.display(34, weight: .bold, relativeTo: .largeTitle))
                        .accessibilityLabel(Text("Amount \(Fmt.cop(fine.amount))"))
                }

                if fine.status == .pending {
                    Timeline(fine: fine)
                        .padding(.horizontal, Metrics.gutter)
                }

                VStack(spacing: 0) {
                    InfoRow(label: "Fine number", value: fine.simitRef)
                    Divider().padding(.leading, 18)
                    InfoRow(label: "Date", value: Fmt.shortDate(fine.issuedAt))
                    if let place = fine.place {
                        Divider().padding(.leading, 18)
                        InfoRow(label: "Place", value: place)
                    }
                    Divider().padding(.leading, 18)
                    InfoRow(label: "Status", value: L10n.status(fine.status))
                }
                .sappaCard()
                .padding(.horizontal, Metrics.gutter)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Data from SIMIT. Always verify on the official site.")
                    NotAffiliatedNote()
                }
                .font(.footnote)
                .foregroundStyle(Color.sTextSecondary)
                .padding(.horizontal, Metrics.gutter)
            }
            .padding(.bottom, 110)
        }
        .background(Color.sBackground)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L10n.status(fine.status))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .sappaGlass(in: Capsule())
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(fine)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("Share"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if fine.status == .pending {
                bottomBar(fine)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear { model.acknowledge(fine) }
        .confirmationDialog("Mark this fine as paid?", isPresented: $confirmPaid, titleVisibility: .visible) {
            Button("Yes, I paid it") { Task { await model.markPaid(fine) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We’ll stop reminding you about it. SIMIT can take a few days to show the payment.")
        }
    }

    private func bottomBar(_ fine: Fine) -> some View {
        HStack(spacing: 12) {
            Link(destination: SimitLinks.payment) {
                Label("Pay on SIMIT", systemImage: "arrow.up.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
            }
            .glassEffect(.regular.tint(.black.opacity(0.4)).interactive(), in: Capsule())
            Button {
                Task { reminderSet = await model.remindBeforeDeadline(fine) }
            } label: {
                Image(systemName: reminderSet ? "bell.fill" : "bell")
                    .font(.title3)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .sappaGlass(in: Circle(), interactive: true)
            .accessibilityLabel(Text("Remind me before the deadline"))
            .disabled(fine.discount.stage == .full)
            Button { confirmPaid = true } label: {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.sAccentGreen)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .sappaGlass(in: Circle(), interactive: true)
            .accessibilityLabel(Text("I already paid it"))
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
    }

    private func title(_ fine: Fine) -> String {
        if let description = fine.infractionDescription {
            return "\(fine.infractionCode) · \(description)"
        }
        return fine.infractionCode
    }

    private func shareText(_ fine: Fine) -> String {
        var parts = [String(localized: "Fine \(fine.simitRef) · \(fine.plate)"), title(fine), Fmt.cop(fine.amount)]
        if let place = fine.place { parts.append(place) }
        parts.append(SimitLinks.payment.absoluteString)
        return parts.joined(separator: "\n")
    }
}

private struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Color.sTextSecondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

/// "Cuánto pagas según cuándo": 50% → 25% → full value.
private struct Timeline: View {
    let fine: Fine

    var body: some View {
        let d = fine.discount
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW MUCH YOU PAY, BY WHEN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sTextSecondary)
            Step(active: d.stage == .fifty, done: d.stage != .fifty,
                 title: "50% off",
                 detail: d.stage == .fifty
                    ? String(localized: "Now · Until \(Fmt.deadline(d.fiftyUntil)) · \(Int(d.businessDaysLeft)) business days. Requires the traffic course.")
                    : String(localized: "Ended \(Fmt.deadline(d.fiftyUntil))"))
            Step(active: d.stage == .twentyFive, done: d.stage == .full,
                 title: "25% off",
                 detail: String(localized: "Until \(Fmt.deadline(d.twentyFiveUntil)). Requires the traffic course."))
            Step(active: d.stage == .full, done: false, isLast: true,
                 title: "Full amount",
                 detail: String(localized: "After \(Fmt.deadline(d.twentyFiveUntil)), plus interest"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .sappaCard()
    }

    private struct Step: View {
        let active: Bool
        let done: Bool
        var isLast = false
        let title: LocalizedStringKey
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(active ? Color.sAccentGreen : Color.clear)
                    .overlay(Circle().stroke(active ? Color.sAccentGreen : Color.sSeparator, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                        .foregroundStyle(done ? Color.sTextSecondary : Color.sTextPrimary)
                        .strikethrough(done)
                    Text(detail).font(.footnote).foregroundStyle(Color.sTextSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(active ? .isSelected : [])
        }
    }
}
