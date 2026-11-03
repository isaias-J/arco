import SwiftUI
import SwiftData
import ArcoCore

/// Asistencia (spec §14): resumen, cumplimiento del plan, confirmación manual, descanso
/// puntual y calendario anual. Todo se calcula desde los registros reales.
struct AttendanceView: View {
    @Environment(AppState.self) private var appState
    @Query private var events: [AttendanceEventModel]
    @Query private var templates: [RoutineTemplateModel]
    @Query private var resolutions: [AttendanceResolutionModel]
    @Query private var sessions: [WorkoutSessionModel]

    private var calendar: Calendar { appState.calendar }
    private var today: CivilDay { CivilDay(Date(), calendar: calendar) }
    private var plan: WeeklyPlan { WeeklyPlan(templates: templates) }

    private var attendanceDays: [AttendanceDay] {
        let tuples = events.map { (date: $0.trainingDate, source: AttendanceSource(rawValue: $0.sourceRaw) ?? .manual, partial: $0.isPartial) }
        return AttendanceEngine.consolidate(events: tuples, calendar: calendar).sorted { $0.date > $1.date }
    }

    private var todayState: CalendarDayState {
        let days = attendanceDays.filter { CivilDay($0.date, calendar: calendar) == today }
        let sources = days.first?.sources ?? []
        var res: [CivilDay: AttendanceResolutionKind] = [:]
        for r in resolutions { if let d = CivilDay(key: r.dayKey), let k = AttendanceResolutionKind(rawValue: r.kindRaw) { res[d] = k } }
        return CalendarStateResolver.state(
            of: today, plan: plan, today: today, calendar: calendar,
            automaticDays: sources.contains(.automatic) ? [today] : [],
            manualDays: sources.contains(.manual) ? [today] : [],
            resolutions: res
        )
    }

    /// Métricas de las últimas 4 semanas con el plan vigente; los días futuros no cuentan.
    private var adherence: AdherenceMetrics {
        let start = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: Date())) ?? Date()
        let planned = plan.plannedTrainingDates(from: start, days: 28, calendar: calendar).filter { $0 <= Date() }
        let plannedDays = Set(planned.map { CivilDay($0, calendar: calendar) })
        let attended = Set(attendanceDays.map { CivilDay($0.date, calendar: calendar) }).filter { $0 >= CivilDay(start, calendar: calendar) }
        let completed = sessions.filter { $0.stateRaw == "finished" && $0.trainingDate >= start }
            .map { CivilDay($0.trainingDate, calendar: calendar) }
        return AdherenceMetrics(
            attendedDays: attended.count,
            completedSessions: Set(completed).intersection(plannedDays).count,
            plannedDays: plannedDays.count
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summaryCard
                    todayCard
                    calendarCard
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
                Text("Últimas 4 semanas").font(.headline)
                let a = adherence
                LabeledContent("Días asistidos", value: "\(a.attendedDays)")
                LabeledContent("Días planificados hasta hoy", value: "\(a.plannedDays)")
                LabeledContent("Sesiones completas en días planificados", value: "\(a.completedSessions)")
                if let c = a.compliance {
                    LabeledContent("Cumplimiento del plan", value: c.formatted(.percent.precision(.fractionLength(0))))
                } else {
                    Text("Sin días planificados en este periodo: no se calcula cumplimiento.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Una sesión parcial cuenta como día asistido; el cumplimiento exige finalizar la sesión. Los descansos planificados no cuentan en contra.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
    }

    private var todayCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Hoy").font(.headline)
                Label(todayState.shortLabel, systemImage: todayState.symbolName)
                    .accessibilityIdentifier("attendance.todayState")
                HStack {
                    Button("Sí fui") {
                        appState.attendance.markAttended(today)
                        Task { await appState.refreshReminders() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(todayState == .manualAttendance || todayState == .trainedRegistered)
                    .accessibilityIdentifier("attendance.didAttend")
                    Button("Hoy descansé") {
                        appState.attendance.markResolution(.rest, on: today)
                        Task { await appState.refreshReminders() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(todayState == .confirmedRest || todayState == .trainedRegistered)
                    .accessibilityIdentifier("attendance.didRest")
                }
                if todayState == .manualAttendance {
                    Button("Deshacer \"Sí fui\"", role: .destructive) {
                        appState.attendance.removeManualAttendance(today)
                        Task { await appState.refreshReminders() }
                    }
                    .font(.footnote)
                }
                if todayState == .confirmedRest {
                    Button("Deshacer descanso", role: .destructive) {
                        appState.attendance.removeResolution(today)
                        Task { await appState.refreshReminders() }
                    }
                    .font(.footnote)
                }
                Text("\"Sí fui\" marca el día como asistido sin inventar series. Cualquiera de las dos respuestas cancela la revisión nocturna de hoy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var calendarCard: some View {
        ArcoCard {
            NavigationLink {
                AnnualCalendarView()
            } label: {
                HStack {
                    Label("Calendario anual", systemImage: "calendar")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("attendance.calendar")
        }
    }

    private var recentCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Días recientes").font(.headline)
                if attendanceDays.isEmpty {
                    Text("Todavía no hay días registrados.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(attendanceDays.prefix(10), id: \.date) { day in
                        HStack {
                            Text(day.date.formatted(.dateTime.weekday().day().month()))
                            Spacer()
                            if day.sources.contains(.automatic) {
                                Label("con series", systemImage: "figure.strengthtraining.traditional").labelStyle(.iconOnly).foregroundStyle(ArcoColor.brand)
                            }
                            if day.sources.contains(.manual) {
                                Label("manual", systemImage: "hand.raised").labelStyle(.iconOnly).foregroundStyle(.secondary)
                            }
                            if day.sessionCount > 1 { Text("\(day.sessionCount) registros").font(.caption2).foregroundStyle(.secondary) }
                            if day.isPartial { Text("parcial").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
