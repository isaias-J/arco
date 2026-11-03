import SwiftUI
import SwiftData
import ArcoCore

/// Historial de altura (spec §18, T58). Cada altura conserva su fecha y unidad: el IMC de un
/// pesaje usa la altura vigente en esa fecha; una altura nueva no recalcula el pasado en silencio.
struct HeightHistoryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \HeightModel.date, order: .reverse) private var heights: [HeightModel]
    @State private var showAdd = false

    var body: some View {
        List {
            if heights.isEmpty {
                ContentUnavailableView {
                    Label("Sin altura registrada", systemImage: "ruler")
                } description: {
                    Text("Añade tu altura para calcular el IMC. Es opcional.")
                } actions: {
                    Button("Añadir altura") { showAdd = true }
                }
            } else {
                Section {
                    ForEach(heights) { h in
                        HeightRow(height: h, displayUnit: appState.settings.lengthUnit)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("El IMC de cada pesaje usa la altura vigente en su fecha. Si no hay una anterior, se usa la primera conocida y se indica como supuesto.")
                }
            }
        }
        .navigationTitle("Altura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("Añadir altura", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddHeightView() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { appState.context.delete(heights[index]) }
        try? appState.context.save()
    }
}

private struct HeightRow: View {
    let height: HeightModel
    let displayUnit: LengthUnit

    private var original: LengthUnit { LengthUnit(rawValue: height.unitRaw) ?? .centimeters }

    var body: some View {
        HStack {
            Text(ProfileFormat.date(height.date))
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(ProfileFormat.number(ProfileFormat.length(height.amount, from: original, to: displayUnit))) \(displayUnit.rawValue)")
                    .monospacedDigit()
                if original != displayUnit {
                    Text("registrado: \(ProfileFormat.number(height.amount)) \(original.rawValue)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Alta de altura: valor > 0, fecha ≤ hoy, unidad de longitud configurada.
struct AddHeightView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var date = Date()
    @State private var showError = false

    private var outcome: BodyValueValidation.Outcome { BodyValueValidation.validate(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Altura", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text(appState.settings.lengthUnit.rawValue).foregroundStyle(.secondary)
                    }
                    DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    if showError, let message = BodyValueValidation.message(for: outcome) {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Añadir altura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(outcome == .empty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard case .valid(let amount) = outcome else { showError = true; return }
        appState.context.insert(HeightModel(date: min(date, Date()), amount: amount, unitRaw: appState.settings.lengthUnit.rawValue))
        try? appState.context.save()
        dismiss()
    }
}
