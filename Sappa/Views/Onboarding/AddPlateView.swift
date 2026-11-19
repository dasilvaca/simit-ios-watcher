import SwiftUI
import SappaCore

/// Screen 1 · Agregar placa. Also used from the "+" button.
struct AddPlateView: View {
    enum Mode { case onboarding, add }

    let mode: Mode
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var kind: VehicleKind = .moto
    @State private var plate = ""
    @State private var nickname = ""
    @State private var errorText: String?
    @FocusState private var plateFocused: Bool

    private var validation: PlateValidation { validatePlate(plate: plate, kind: kind) }
    private var isValid: Bool { validation.error == nil && !plate.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderPanel(tone: .clear) {
                    if mode == .onboarding {
                        StepIndicator(step: 1, of: 2)
                    }
                    Text("Which vehicle should we watch?")
                        .font(.largeTitle.bold())
                    Text("Just the plate. No ID number, no accounts, no passwords.")
                        .font(.body)
                        .foregroundStyle(HeaderTone.clear.inkSecondary)

                    Picker("Vehicle type", selection: $kind) {
                        Text("Motorcycle").tag(VehicleKind.moto)
                        Text("Car").tag(VehicleKind.car)
                    }
                    .pickerStyle(.segmented)
                    .padding(4)
                    .sappaGlass(in: Capsule())

                    Text("Plate")
                        .font(.subheadline.weight(.semibold))
                    PlateInput(text: $plate, kind: kind, focused: $plateFocused)
                    ValidationLine(plate: plate, kind: kind, validation: validation)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nickname (optional)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.sTextSecondary)
                    TextField("e.g. Main motorcycle", text: $nickname)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 52)
                        .background(Capsule().fill(Color.sSurface))
                        .submitLabel(.done)
                }
                .padding(.horizontal, Metrics.gutter)

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Color.sRust)
                        .padding(.horizontal, Metrics.gutter)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.sBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Label("Your plates are stored only on this iPhone.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(Color.sTextSecondary)
                Button("Continue", action: submit)
                    .buttonStyle(.sappaPrimary)
                    .disabled(!isValid)
                    .accessibilityIdentifier("continue")
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
            .background(Color.sBackground.opacity(0.92))
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if mode == .add {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: onDone)
                }
            }
        }
        .onChange(of: plate) { _, newValue in
            errorText = nil
            // Switch kind when the shape clearly says so (ABC123 = car, ABC12D = moto).
            if newValue.count == 6, let detected = detectVehicleKind(plate: newValue), detected != kind {
                kind = detected
            }
        }
    }

    private func submit() {
        do {
            _ = try model.addVehicle(plate: plate, kind: kind, nickname: nickname)
            if mode == .add {
                Task { await model.checkNow() }
            }
            onDone()
        } catch CoreError.DuplicatePlate {
            errorText = String(localized: "This plate is already on your list.")
        } catch CoreError.InvalidPlate {
            errorText = String(localized: "Check the plate format.")
        } catch {
            errorText = String(localized: "Could not save the plate. Try again.")
        }
    }
}

struct StepIndicator: View {
    let step: Int
    let of: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("Step \(step) of \(of)")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(1...of, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.sAccentGreen : Color.sAccentGreen.opacity(0.25))
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// Big yellow plate field: 3 pt black border, radius 18, 52 pt Space Grotesk, "COLOMBIA" caption.
struct PlateInput: View {
    @Binding var text: String
    let kind: VehicleKind
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 2) {
            TextField(kind == .moto ? "TTO08G" : "ABC123", text: $text)
                .font(.display(52, weight: .bold, relativeTo: .largeTitle))
                .tracking(3)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused(focused)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(Text("Plate"))
                .accessibilityIdentifier("plateField")
                .onChange(of: text) { _, newValue in
                    let cleaned = String(newValue.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(6))
                    if cleaned != newValue { text = cleaned }
                }
            Text("COLOMBIA")
                .font(.display(12, weight: .semibold, relativeTo: .caption))
                .tracking(4)
        }
        .foregroundStyle(Color.sPlateInk)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.sPlateYellow))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.sPlateInk, lineWidth: 3))
        .onTapGesture { focused.wrappedValue = true }
    }
}

struct ValidationLine: View {
    let plate: String
    let kind: VehicleKind
    let validation: PlateValidation

    var body: some View {
        Group {
            if plate.isEmpty {
                Label(kind == .moto ? "Motorcycle format: ABC12D" : "Car format: ABC123", systemImage: "info.circle")
                    .foregroundStyle(HeaderTone.clear.inkSecondary)
            } else if validation.error == nil {
                Label(kind == .moto ? "Valid motorcycle format (ABC12D)" : "Valid car format (ABC123)",
                      systemImage: "checkmark")
                    .foregroundStyle(Color.sGreenText)
            } else if plate.count < 6 {
                Label(kind == .moto ? "Motorcycle format: ABC12D" : "Car format: ABC123", systemImage: "info.circle")
                    .foregroundStyle(HeaderTone.clear.inkSecondary)
            } else {
                Label(kind == .moto ? "Use the format ABC12D" : "Use the format ABC123",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.sRust)
            }
        }
        .font(.subheadline.weight(.medium))
        .accessibilityIdentifier("plateValidation")
    }
}
