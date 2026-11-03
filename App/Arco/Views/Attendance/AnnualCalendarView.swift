import SwiftUI
import SwiftData
import ArcoCore

/// Calendario anual de asistencia (spec §14), tipo "mapa de contribuciones" adaptado a móvil:
/// meses identificados, desplazamiento, leyenda, detalle al tocar una celda y selector de año.
/// También ofrece vista mensual para una consulta más cómoda.
///
/// Honestidad (spec §14):
/// - El color representa asistencia O cantidad de series, con el MODO identificado (Picker).
///   No se equipara "más color = mejor": cada celda lleva símbolo/estado además del color.
/// - No se muestra ausencia automáticamente por falta de datos. Los días futuros = estado futuro.
/// - Se cruzan eventos (@Query) con la rutina (RoutineTemplateModel) para distinguir planificado
///   vs descanso. Año bisiesto y límites de semana/mes se manejan con Calendar + startOfDay.
struct AnnualCalendarView: View {
    @Environment(AppState.self) private var appState
    @Query private var events: [AttendanceEventModel]
    @Query private var sessions: [WorkoutSessionModel]
    @Query private var templates: [RoutineTemplateModel]
    @Query private var resolutions: [AttendanceResolutionModel]

    @State private var year: Int
    @State private var layout: CalendarLayout = .year
    @State private var colorMode: CalendarColorMode = .attendance
    @State private var selectedDay: DayCellInfo?

    init(year: Int? = nil) {
        _year = State(initialValue: year ?? Calendar.current.component(.year, from: Date()))
    }

    /// Calendario de la app (semana desde lunes por defecto, configurable — spec §14).
    private var calendar: Calendar { appState.calendar }

    // MARK: - Modelo de días

    /// Mapa fecha→AttendanceDay consolidado (varias sesiones el mismo día = un día, T35).
    private var attendanceByDay: [Date: AttendanceDay] {
        let tuples = events.map {
            (date: $0.trainingDate, source: AttendanceSource(rawValue: $0.sourceRaw) ?? .manual, partial: $0.isPartial)
        }
        let days = AttendanceEngine.consolidate(events: tuples, calendar: calendar)
        var map: [Date: AttendanceDay] = [:]
        for d in days { map[calendar.startOfDay(for: d.date)] = d }
        return map
    }

    /// Nº de series de trabajo elegibles por día (para el modo "series").
    private var workSetsByDay: [Date: Int] {
        var map: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.trainingDate)
            let count = session.exercises
                .flatMap { $0.sets }
                .filter { $0.toDomain().isEligibleForWorkCount }
                .count
            if count > 0 { map[day, default: 0] += count }
        }
        return map
    }

    /// Máximo de series en el año (para escalar la intensidad del modo "series").
    private var maxWorkSetsInYear: Int {
        workSetsByDay
            .filter { calendar.component(.year, from: $0.key) == year }
            .map { $0.value }
            .max() ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                controls
                legend
                if layout == .year {
                    yearGrid
                } else {
                    monthList
                }
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDay) { info in
            DayDetailSheet(info: info)
                .presentationDetents([.height(280), .medium])
        }
    }

    // MARK: - Controles (año, vista, modo de color)

    private var controls: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Button {
                    year -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Año anterior")

                Spacer()
                Text(String(year))
                    .font(.title2.bold())
                    .monospacedDigit()
                Spacer()

                Button {
                    year += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Año siguiente")
                .disabled(year >= calendar.component(.year, from: Date()))
            }

            Picker("Vista", selection: $layout) {
                ForEach(CalendarLayout.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            // Modo de color identificado explícitamente (spec §14).
            Picker("Modo de color", selection: $colorMode) {
                ForEach(CalendarColorMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("El color representa \(colorMode.label)")
        }
    }

    private var legend: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Leyenda · el color representa \(colorMode.label.lowercased())")
                    .font(.caption.bold())
                // Estados con símbolo + color (no solo color — accesibilidad, spec §14).
                FlowLegend(items: CalendarDayState.legendItems)
                Text("Más intensidad no significa un entrenamiento \"mejor\". Cada día lleva su estado y símbolo.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Vista anual (meses en cuadrícula de celdas)

    private var yearGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(1...12, id: \.self) { month in
                MonthGrid(
                    year: year,
                    month: month,
                    calendar: calendar,
                    colorMode: colorMode,
                    maxWorkSets: maxWorkSetsInYear,
                    dayInfo: dayInfo(for:),
                    onSelect: { selectedDay = $0 }
                )
            }
        }
    }

    // MARK: - Vista mensual (una lista con filas por día)

    private var monthList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(1...12, id: \.self) { month in
                DisclosureGroup(monthName(month)) {
                    let days = daysInMonth(month: month)
                    ForEach(days, id: \.self) { date in
                        let info = dayInfo(for: date)
                        Button {
                            selectedDay = info
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: info.state.symbolName)
                                    .foregroundStyle(cellColor(for: info))
                                    .frame(width: 20)
                                Text(date.formatted(.dateTime.weekday().day().month()))
                                Spacer()
                                Text(info.state.shortLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(info.accessibilityText)
                    }
                }
                .font(.subheadline.bold())
            }
        }
    }

    // MARK: - Cálculo de estado por día

    /// Determina el estado de un día con la regla compartida y probada del núcleo
    /// (`CalendarStateResolver`, spec §14): plan semanal con la convención única de weekday,
    /// resoluciones guardadas ("Hoy descansé") y sin ausencias inventadas por falta de datos.
    private func dayInfo(for date: Date) -> DayCellInfo {
        let day = calendar.startOfDay(for: date)
        let civil = CivilDay(day, calendar: calendar)
        let attendance = attendanceByDay[day]
        let workSets = workSetsByDay[day] ?? 0
        let sources = attendance?.sources ?? []

        let state = CalendarStateResolver.state(
            of: civil,
            plan: WeeklyPlan(templates: templates),
            today: CivilDay(Date(), calendar: calendar),
            calendar: calendar,
            automaticDays: sources.contains(.automatic) ? [civil] : [],
            manualDays: sources.contains(.manual) ? [civil] : [],
            resolutions: resolutionsByDay
        )

        return DayCellInfo(
            date: day,
            state: state,
            sessionCount: attendance?.sessionCount ?? 0,
            isPartial: attendance?.isPartial ?? false,
            workSetCount: workSets,
            sources: sources
        )
    }

    private var resolutionsByDay: [CivilDay: AttendanceResolutionKind] {
        var map: [CivilDay: AttendanceResolutionKind] = [:]
        for r in resolutions {
            if let d = CivilDay(key: r.dayKey), let k = AttendanceResolutionKind(rawValue: r.kindRaw) { map[d] = k }
        }
        return map
    }

    /// Color de la celda según el modo. En "series" la intensidad escala con el recuento.
    private func cellColor(for info: DayCellInfo) -> Color {
        CalendarPalette.color(for: info, mode: colorMode, maxWorkSets: maxWorkSetsInYear)
    }

    // MARK: - Utilidades de fechas

    private func daysInMonth(month: Int) -> [Date] {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let start = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        return range.compactMap { day -> Date? in
            var c = comps
            c.day = day
            return calendar.date(from: c)
        }
    }

    private func monthName(_ month: Int) -> String {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = calendar.date(from: comps) else { return "" }
        return date.formatted(.dateTime.month(.wide)).capitalized
    }
}

// MARK: - Cuadrícula de un mes

/// Cuadrícula de celdas de un mes, con semanas en columnas y días alineados por weekday
/// (maneja año bisiesto y el primer weekday configurable — spec §14).
private struct MonthGrid: View {
    let year: Int
    let month: Int
    let calendar: Calendar
    let colorMode: CalendarColorMode
    let maxWorkSets: Int
    let dayInfo: (Date) -> DayCellInfo
    let onSelect: (DayCellInfo) -> Void

    private let cellSize: CGFloat = 26
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 7)

    private var monthName: String {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let date = calendar.date(from: comps) else { return "" }
        return date.formatted(.dateTime.month(.wide)).capitalized
    }

    /// Días reales del mes (sin huecos de relleno). Alinea el primer día a su weekday.
    private var dates: [Date] {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let start = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        return range.compactMap { d in
            var c = comps; c.day = d; return calendar.date(from: c)
        }
    }

    /// Offset de relleno al inicio para alinear el primer día bajo su columna de weekday.
    private var leadingBlanks: Int {
        guard let first = dates.first else { return 0 }
        let weekdayIndex = calendar.component(.weekday, from: first) // 1=domingo … 7=sábado
        // Columna 0 = primer weekday del calendario.
        return (weekdayIndex - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(monthName)
                .font(.subheadline.bold())
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
                ForEach(dates, id: \.self) { date in
                    let info = dayInfo(date)
                    DayCell(
                        info: info,
                        size: cellSize,
                        color: CalendarPalette.color(for: info, mode: colorMode, maxWorkSets: maxWorkSets)
                    )
                    .onTapGesture { onSelect(info) }
                }
            }
        }
    }
}

/// Una celda del calendario. Usa fecha como id estable (skill). Lleva color + símbolo + número
/// de día, y una etiqueta de accesibilidad con fecha y estado.
private struct DayCell: View {
    let info: DayCellInfo
    let size: CGFloat
    let color: Color

    private var dayNumber: Int {
        Calendar.current.component(.day, from: info.date)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
            // Símbolo de estado además del color (accesibilidad, spec §14).
            if info.state == .trainedRegistered || info.state == .manualAttendance {
                Image(systemName: info.state.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(dayNumber)")
                    .font(.system(size: 9))
                    .foregroundStyle(info.state == .future ? .secondary : ArcoColor.textSecondary)
            }
            if info.isPartial {
                // Marca de sesión parcial en una esquina.
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(ArcoColor.chartSecondary)
                            .frame(width: 5, height: 5)
                    }
                    Spacer()
                }
                .padding(2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.accessibilityText)
    }
}

// MARK: - Leyenda

private struct FlowLegend: View {
    let items: [(state: CalendarDayState, color: Color)]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.sm, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.xs) {
            ForEach(items, id: \.state) { item in
                HStack(spacing: Spacing.xs) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(item.color)
                        .frame(width: 14, height: 14)
                    Image(systemName: item.state.symbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(item.state.shortLabel)
                        .font(.caption2)
                }
            }
        }
    }
}

// MARK: - Hoja de detalle de un día

/// Detalle al tocar una celda (spec §14): fecha, estado, nº de sesiones y series del día.
struct DayDetailSheet: View {
    let info: DayCellInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Fecha", value: info.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    LabeledContent("Estado", value: info.state.shortLabel)
                }
                Section("Actividad") {
                    LabeledContent("Sesiones", value: "\(info.sessionCount)")
                    LabeledContent("Series de trabajo", value: "\(info.workSetCount)")
                    if info.isPartial {
                        Text("Alguna sesión quedó parcial.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if info.sources.contains(.manual) {
                        Text("Incluye una confirmación manual (\"sí fui\").")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if info.state == .plannedUnconfirmed {
                    Section {
                        Text("Día planificado sin registro. No se marca como ausencia solo por no tener datos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Detalle del día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Modelos de apoyo (UI)

/// Información de una celda/día (id estable = fecha, spec: celdas usan la fecha como id).
struct DayCellInfo: Identifiable {
    let date: Date
    let state: CalendarDayState
    let sessionCount: Int
    let isPartial: Bool
    let workSetCount: Int
    let sources: Set<AttendanceSource>
    var id: Date { date }

    /// Texto de accesibilidad: fecha + estado (+ series si aplica).
    var accessibilityText: String {
        var parts = [date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()), state.shortLabel]
        if workSetCount > 0 {
            parts.append("\(workSetCount) series")
        }
        if isPartial {
            parts.append("sesión parcial")
        }
        return parts.joined(separator: ", ")
    }
}

/// Vista anual vs mensual.
enum CalendarLayout: String, CaseIterable, Identifiable {
    case year, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .year: return "Año"
        case .month: return "Mes"
        }
    }
}

/// Modo de color: asistencia (estado) o cantidad de series. El modo se identifica (spec §14).
enum CalendarColorMode: String, CaseIterable, Identifiable {
    case attendance, series
    var id: String { rawValue }
    var label: String {
        switch self {
        case .attendance: return "Asistencia"
        case .series: return "Series"
        }
    }
}

// MARK: - Paleta y etiquetas de estado

extension CalendarDayState {
    var shortLabel: String {
        switch self {
        case .trainedRegistered: return "Entrenamiento registrado"
        case .manualAttendance: return "Asistencia manual"
        case .plannedRest: return "Descanso planificado"
        case .confirmedRest: return "Descanso confirmado"
        case .plannedUnconfirmed: return "Planificado sin registro"
        case .confirmedAbsence: return "Ausencia confirmada"
        case .future: return "Futuro"
        }
    }

    /// Símbolo que acompaña al color (no depender solo del color — accesibilidad, spec §14).
    var symbolName: String {
        switch self {
        case .trainedRegistered: return "figure.strengthtraining.traditional"
        case .manualAttendance: return "hand.raised.fill"
        case .plannedRest: return "moon.zzz"
        case .confirmedRest: return "moon.zzz.fill"
        case .plannedUnconfirmed: return "questionmark"
        case .confirmedAbsence: return "xmark"
        case .future: return "circle.dotted"
        }
    }

    /// Estados mostrados en la leyenda (los relevantes para esta versión).
    static var legendItems: [(state: CalendarDayState, color: Color)] {
        let states: [CalendarDayState] = [
            .trainedRegistered, .manualAttendance, .plannedRest, .confirmedRest, .plannedUnconfirmed, .future
        ]
        return states.map { ($0, CalendarPalette.baseColor(for: $0)) }
    }
}

/// Paleta del calendario. No equipara "más color = mejor": el color codifica estado o volumen,
/// siempre acompañado de símbolo/etiqueta (spec §14).
enum CalendarPalette {
    static func baseColor(for state: CalendarDayState) -> Color {
        switch state {
        case .trainedRegistered: return ArcoColor.brand
        case .manualAttendance: return ArcoColor.chart
        case .plannedRest: return ArcoColor.chartSecondary.opacity(0.35)
        case .confirmedRest: return ArcoColor.chartSecondary.opacity(0.55)
        case .plannedUnconfirmed: return ArcoColor.surface
        case .confirmedAbsence: return Color.gray.opacity(0.4)
        case .future: return ArcoColor.surface.opacity(0.5)
        }
    }

    static func color(for info: DayCellInfo, mode: CalendarColorMode, maxWorkSets: Int) -> Color {
        switch mode {
        case .attendance:
            return baseColor(for: info.state)
        case .series:
            // Intensidad por volumen de series; días sin series usan el color de estado.
            guard info.workSetCount > 0, maxWorkSets > 0 else {
                return baseColor(for: info.state)
            }
            let ratio = min(1.0, Double(info.workSetCount) / Double(maxWorkSets))
            // Rango 0.3…1.0 de opacidad para que incluso pocas series sean visibles.
            return ArcoColor.chart.opacity(0.3 + 0.7 * ratio)
        }
    }
}

// MARK: - Preview

#Preview("Calendario anual") {
    let container = try! ModelContainer(
        for: AttendanceEventModel.self, WorkoutSessionModel.self, SessionExerciseModel.self,
        SetRecordModel.self, RoutineTemplateModel.self, AppSettingsModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let calendar = Calendar.current

    // Rutina con la convención de Calendar: jueves (5) y domingo (1) descanso.
    for wd in 1...7 {
        context.insert(RoutineTemplateModel(
            id: "tpl_\(wd)", name: "Día \(wd)", weekday: wd,
            groupsJoined: "chest", isRestDay: (wd == 5 || wd == 1)
        ))
    }

    // Unos días asistidos recientes (automático y manual, uno parcial).
    for (offset, auto, partial) in [(-2, true, false), (-4, true, true), (-6, false, false)] {
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        context.insert(AttendanceEventModel(
            trainingDate: calendar.startOfDay(for: date),
            sourceRaw: auto ? "automatic" : "manual",
            isPartial: partial
        ))
        if auto {
            let set = SetRecordModel(
                loadAmount: 60, loadUnitRaw: "kg", loadConventionRaw: "externalTotal",
                reps: 8, typeRaw: "working", stateRaw: "completed", sideRaw: "bilateral",
                performedAt: date
            )
            let se = SessionExerciseModel(exerciseID: "chest_flat_barbell", order: 0, sets: [set])
            context.insert(WorkoutSessionModel(startedAt: date, trainingDate: calendar.startOfDay(for: date), originTimeZoneID: "UTC", exercises: [se]))
        }
    }

    return NavigationStack {
        AnnualCalendarView()
    }
    .environment(AppState(context: context))
    .modelContainer(container)
}
