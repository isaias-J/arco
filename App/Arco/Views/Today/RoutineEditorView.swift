import SwiftUI
import SwiftData
import ArcoCore

/// Editor de la rutina semanal con historial (spec §2, §14, T39). Guardar crea una versión del
/// plan vigente desde hoy; las fechas anteriores se siguen evaluando con la versión previa.
struct RoutineEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [Weekday: DayDraft] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var saving = false

    private struct DayDraft: Equatable {
        var isRest: Bool
        var groups: Set<MuscleGroup>
    }

    private var days: [Weekday] { Weekday.ordered(startingMonday: appState.settings.weekStartsMonday) }

    /// Días de entrenamiento sin ningún grupo elegido (no se pueden guardar así).
    private var incompleteDays: [Weekday] {
        days.filter { d in
            guard let draft = drafts[d] else { return false }
            return !draft.isRest && draft.groups.isEmpty
        }
    }

    var body: some View {
        Form {
            Section {
                Text("El cambio aplica desde hoy; los días anteriores conservan la rutina que tenían.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                daySection(day)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Editar rutina")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .disabled(saving || drafts.isEmpty)
                    .accessibilityIdentifier("routine.save")
            }
        }
        .onAppear(perform: load)
    }

    private func daySection(_ day: Weekday) -> some View {
        let draft = drafts[day] ?? DayDraft(isRest: true, groups: [])
        return Section {
            Toggle("Descanso", isOn: Binding(
                get: { drafts[day]?.isRest ?? true },
                set: { drafts[day, default: DayDraft(isRest: true, groups: [])].isRest = $0 }
            ))
            .accessibilityLabel("\(day.displayName): descanso")
            .accessibilityIdentifier("routine.rest.\(day.rawValue)")
            if !draft.isRest {
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let selected = draft.groups.contains(group)
                    Button {
                        if selected { drafts[day]?.groups.remove(group) } else { drafts[day]?.groups.insert(group) }
                    } label: {
                        HStack {
                            Text(group.displayName).foregroundStyle(ArcoColor.textPrimary)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? ArcoColor.brand : .secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("routine.group.\(day.rawValue).\(group.rawValue)")
                }
                if draft.groups.isEmpty {
                    Text("Elige al menos un grupo o marca el día como descanso.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(day.displayName)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let plan = appState.planHistory.plan(on: Date()) ?? appState.weeklyPlan
        var result: [Weekday: DayDraft] = [:]
        for day in Weekday.allCases {
            let d = plan.day(for: day)
            result[day] = DayDraft(isRest: d?.isRest ?? true, groups: Set(d?.groups ?? []))
        }
        drafts = result
    }

    private func save() {
        guard incompleteDays.isEmpty else {
            error = "Falta elegir grupos en: \(incompleteDays.map(\.displayName).joined(separator: ", "))."
            return
        }
        saving = true
        // Orden estable de grupos (el del catálogo de grupos) para que el plan sea reproducible.
        let plan = WeeklyPlan(days: Weekday.allCases.map { day in
            let d = drafts[day] ?? DayDraft(isRest: true, groups: [])
            return WeeklyPlan.Day(weekday: day, isRest: d.isRest, groups: d.isRest ? [] : MuscleGroup.allCases.filter { d.groups.contains($0) })
        })
        do {
            try appState.catalog.updatePlan(plan, effective: Date(), calendar: appState.calendar)
            error = nil
            Task {
                await appState.refreshReminders()
                saving = false
                dismiss()
            }
        } catch {
            saving = false
            self.error = "No se pudo guardar la rutina. Tus cambios siguen aquí; vuelve a intentarlo."
        }
    }
}
