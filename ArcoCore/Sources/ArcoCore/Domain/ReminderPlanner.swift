import Foundation

/// Categorías de avisos locales (spec §15).
public enum ReminderCategory: String, Sendable, CaseIterable, Codable {
    case training          // recordatorio de entrenamiento, horario por día
    case review            // revisión de asistencia nocturna
    case photo             // recordatorio semanal de fotos (desactivado por defecto)
    case summary           // resumen semanal (invitación genérica)
}

/// Regla configurada por el usuario. `weekday == nil` aplica a todos los días.
public struct ReminderRule: Sendable, Equatable {
    public let category: ReminderCategory
    public let weekday: Weekday?
    public let hour: Int
    public let minute: Int
    public let enabled: Bool

    public init(category: ReminderCategory, weekday: Weekday?, hour: Int, minute: Int, enabled: Bool) {
        self.category = category
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.enabled = enabled
    }
}

/// Excepción de un aviso para una fecha concreta ("solo hoy" o "Voy más tarde").
public struct ReminderOverride: Sendable, Equatable {
    public let category: ReminderCategory
    public let day: CivilDay
    public let hour: Int
    public let minute: Int
    public let enabled: Bool

    public init(category: ReminderCategory, day: CivilDay, hour: Int, minute: Int, enabled: Bool) {
        self.category = category
        self.day = day
        self.hour = hour
        self.minute = minute
        self.enabled = enabled
    }
}

/// Aviso concreto a programar. El identificador incluye categoría y fecha civil, de modo que
/// cancelar o responder un aviso afecta solo a esa fecha (T41, T42).
public struct PlannedReminder: Sendable, Equatable, Identifiable {
    public let id: String
    public let category: ReminderCategory
    public let day: CivilDay
    public let hour: Int
    public let minute: Int

    public init(category: ReminderCategory, day: CivilDay, hour: Int, minute: Int) {
        self.id = ReminderPlanner.identifier(category, day)
        self.category = category
        self.day = day
        self.hour = hour
        self.minute = minute
    }
}

/// Planificador determinista de avisos (spec §15). iOS no ejecuta código cada noche, así que
/// se programan fechas concretas en una ventana futura y se recalcula al abrir la app, al
/// cambiar ajustes, al registrar asistencia y al responder un aviso.
public enum ReminderPlanner {

    public struct Input: Sendable {
        public var plan: WeeklyPlan
        public var rules: [ReminderRule]
        public var overrides: [ReminderOverride]
        /// Días con asistencia válida (automática o manual).
        public var attendedDays: Set<CivilDay>
        /// Días con descanso puntual o ausencia ya confirmados.
        public var resolvedDays: Set<CivilDay>
        /// Día de entrenamiento de una sesión activa, si existe.
        public var activeSessionDay: CivilDay?
        public var now: Date
        public var calendar: Calendar
        public var horizonDays: Int
        /// Límite de avisos pendientes. iOS admite 64; se deja margen.
        public var limit: Int

        public init(
            plan: WeeklyPlan, rules: [ReminderRule], overrides: [ReminderOverride] = [],
            attendedDays: Set<CivilDay> = [], resolvedDays: Set<CivilDay> = [],
            activeSessionDay: CivilDay? = nil, now: Date, calendar: Calendar,
            horizonDays: Int = 28, limit: Int = 60
        ) {
            self.plan = plan; self.rules = rules; self.overrides = overrides
            self.attendedDays = attendedDays; self.resolvedDays = resolvedDays
            self.activeSessionDay = activeSessionDay; self.now = now; self.calendar = calendar
            self.horizonDays = horizonDays; self.limit = limit
        }
    }

    /// Hora predeterminada de la revisión (spec §15: 21:00 en días planificados).
    public static let defaultReviewHour = 21
    /// Separación mínima entre el recordatorio de entrenamiento y la revisión del mismo día.
    public static let reviewGapAfterTrainingMinutes = 120

    public static func identifier(_ category: ReminderCategory, _ day: CivilDay) -> String {
        "arco.\(category.rawValue).\(day.key)"
    }

    /// Recupera categoría y fecha de un identificador (las acciones se dirigen a esa fecha
    /// aunque se pulsen al día siguiente — T42).
    public static func parse(_ identifier: String) -> (category: ReminderCategory, day: CivilDay)? {
        let parts = identifier.split(separator: ".")
        guard parts.count == 3, parts[0] == "arco",
              let category = ReminderCategory(rawValue: String(parts[1])),
              let day = CivilDay(key: String(parts[2])) else { return nil }
        return (category, day)
    }

    /// Regla vigente para una categoría y día: la específica del día prevalece sobre la general.
    static func rule(_ category: ReminderCategory, _ weekday: Weekday, in rules: [ReminderRule]) -> ReminderRule? {
        rules.first { $0.category == category && $0.weekday == weekday }
            ?? rules.first { $0.category == category && $0.weekday == nil }
    }

    public static func plan(_ input: Input) -> [PlannedReminder] {
        let cal = input.calendar
        let today = CivilDay(input.now, calendar: cal)
        var userChosen: [PlannedReminder] = []
        var reviews: [PlannedReminder] = []

        func override(_ category: ReminderCategory, _ day: CivilDay) -> ReminderOverride? {
            input.overrides.first { $0.category == category && $0.day == day }
        }
        func isFuture(_ day: CivilDay, _ hour: Int, _ minute: Int) -> Bool {
            guard let fire = day.date(hour: hour, minute: minute, in: cal) else { return false }
            return fire > input.now
        }

        for offset in 0..<max(0, input.horizonDays) {
            guard let day = today.adding(days: offset, calendar: cal),
                  let start = day.startDate(in: cal) else { continue }
            let weekday = Weekday.of(start, calendar: cal)
            let planned = input.plan.isPlannedTraining(start, calendar: cal)
            let settled = input.attendedDays.contains(day) || input.resolvedDays.contains(day)

            // 1. Recordatorio de entrenamiento: solo días planificados y aún sin resolver.
            var trainingTime: (Int, Int)?
            if planned, !settled {
                if let o = override(.training, day) {
                    if o.enabled { trainingTime = (o.hour, o.minute) }
                } else if let r = rule(.training, weekday, in: input.rules), r.enabled {
                    trainingTime = (r.hour, r.minute)
                }
                if let (h, m) = trainingTime, isFuture(day, h, m) {
                    userChosen.append(PlannedReminder(category: .training, day: day, hour: h, minute: m))
                }
            }

            // 2. Revisión de asistencia: días planificados, sin asistencia ni resolución y sin
            //    una sesión activa ese día (T38, T41, T44).
            if planned, !settled, input.activeSessionDay != day,
               let r = rule(.review, weekday, in: input.rules), r.enabled {
                var hour = r.hour, minute = r.minute
                if let o = override(.review, day) {
                    // "Voy más tarde": hora aplazada dentro del mismo día (T43).
                    if !o.enabled { hour = -1 } else { hour = o.hour; minute = o.minute }
                } else if let (th, tm) = trainingTime {
                    // Si entrena a la hora de la revisión o después, la revisión se mueve para no
                    // contradecir el recordatorio de entrenamiento (T44).
                    let review = hour * 60 + minute, training = th * 60 + tm
                    if training + 30 > review {
                        let moved = training + reviewGapAfterTrainingMinutes
                        if moved <= 23 * 60 + 59 { hour = moved / 60; minute = moved % 60 } else { hour = -1 }
                    }
                }
                if hour >= 0, isFuture(day, hour, minute) {
                    reviews.append(PlannedReminder(category: .review, day: day, hour: hour, minute: minute))
                }
            }

            // 3. Fotos y resumen semanal: solo si el usuario los activó para ese día.
            for category in [ReminderCategory.photo, .summary] {
                if let r = input.rules.first(where: { $0.category == category && $0.weekday == weekday }),
                   r.enabled, isFuture(day, r.hour, r.minute) {
                    userChosen.append(PlannedReminder(category: category, day: day, hour: r.hour, minute: r.minute))
                }
            }
        }

        // Prioridad a los avisos elegidos por el usuario; las revisiones ocupan el resto.
        let byDate: (PlannedReminder, PlannedReminder) -> Bool = { a, b in
            if a.day != b.day { return a.day < b.day }
            if a.hour != b.hour { return a.hour < b.hour }
            if a.minute != b.minute { return a.minute < b.minute }
            return a.id < b.id
        }
        let chosen = Array(userChosen.sorted(by: byDate).prefix(input.limit))
        let remaining = max(0, input.limit - chosen.count)
        return (chosen + reviews.sorted(by: byDate).prefix(remaining)).sorted(by: byDate)
    }

    /// Hora de un aplazamiento "Voy más tarde" desde `now`. Devuelve nil si cruzaría al día
    /// siguiente del aviso: no se mueve un aviso a otra fecha de forma inadvertida (T43).
    public static func snoozeTime(for day: CivilDay, minutes: Int, now: Date, calendar: Calendar) -> (hour: Int, minute: Int)? {
        let target = now.addingTimeInterval(TimeInterval(minutes * 60))
        guard CivilDay(target, calendar: calendar) == day else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: target)
        return (c.hour ?? 0, c.minute ?? 0)
    }
}
