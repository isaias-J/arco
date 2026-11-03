import SwiftUI
import SwiftData
import ArcoCore

/// Asistencia y calendario (spec §14). Días asistidos, sesiones y cumplimiento del plan.
struct AttendanceView: View {
    @Environment(AppState.self) private var appState
    @Query private var events: [AttendanceEventModel]
    @Query private var templates: [RoutineTemplateModel]

    private var calendar: Calendar { Calendar.current }

    private var attendanceDays: [AttendanceDay] {
        let tuples = events.map { (date: $0.trainingDate, source: AttendanceSource(rawValue: $0.sourceRaw) ?? .manual, partial: $0.isPartial) }
        return AttendanceEngine.consolidate(events: tuples, calendar: calendar)
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summaryCard
                    calendarCard
                    manualCard
                    recentCard
                }
                .padding(Spacing.lg)
            }
            .background(ArcoColor.background)
            .navigationTitle("Asistencia")
        }
    }

    private var summaryCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Resumen").font(.headline)
                let attended = attendanceDays.count
                Text("\(attended) \(attended == 1 ? "día asistido" : "días asistidos")")
                    .font(.title2.bold())
                    .contentTransition(.numericText())
                Text("Las cifras se calculan a partir de tus sesiones reales. Los descansos planificados no rompen tu constancia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var calendarCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Calendario anual").font(.headline)
                Text("Revisa tu asistencia por días y meses. El color indica asistencia o series, con el modo identificado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    AnnualCalendarView()
                } label: {
                    HStack {
                        Label("Ver calendario", systemImage: "calendar")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var manualCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("¿Entrenaste hoy?").font(.headline)
                HStack {
                    Button("Sí fui") { markManual(partial: false) }
                        .buttonStyle(.borderedProminent)
                    Button("Hoy descansé") { markRest() }
                        .buttonStyle(.bordered)
                }
                Text("Registrar \"Sí fui\" no inventa series; solo marca el día como asistido.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recentCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Días recientes").font(.headline)
                if attendanceDays.isEmpty {
                    Text("Todavía no hay días registrados.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(attendanceDays.prefix(10), id: \.date) { day in
                        HStack {
                            Text(day.date.formatted(.dateTime.day().month().weekday()))
                            Spacer()
                            if day.sources.contains(.automatic) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .foregroundStyle(ArcoColor.brand)
                            }
                            if day.sources.contains(.manual) {
                                Image(systemName: "hand.raised").foregroundStyle(.secondary)
                            }
                            if day.isPartial {
                                Text("parcial").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private func markManual(partial: Bool) {
        let day = calendar.startOfDay(for: Date())
        // Evitar duplicar confirmación manual del mismo día.
        let exists = events.contains { $0.sourceRaw == AttendanceSource.manual.rawValue && calendar.isDate($0.trainingDate, inSameDayAs: day) }
        guard !exists else { return }
        appState.context.insert(AttendanceEventModel(trainingDate: day, sourceRaw: AttendanceSource.manual.rawValue, isPartial: partial))
        try? appState.context.save()
    }

    private func markRest() {
        // Descanso puntual confirmado: se registra como excepción (no asistencia).
        // En esta versión se refleja no creando evento; la UI podría ampliarse con un modelo
        // de resolución. Mantener simple y honesto.
    }
}
