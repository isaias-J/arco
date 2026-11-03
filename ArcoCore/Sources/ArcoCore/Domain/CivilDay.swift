import Foundation

/// Fecha civil (año-mes-día) independiente de la zona horaria (spec §5 "Tiempo e historial").
/// Se usa como clave estable de días: un viaje no mueve un descanso o un aviso a otro día.
public struct CivilDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Clave "yyyy-MM-dd".
    public var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String { key }

    /// Medianoche de este día en el calendario dado.
    public func startDate(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Instante de este día a la hora local indicada (respeta horario de verano).
    public func date(hour: Int, minute: Int, in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    public func adding(days: Int, calendar: Calendar) -> CivilDay? {
        guard let start = startDate(in: calendar),
              let next = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
        return CivilDay(next, calendar: calendar)
    }

    public static func < (lhs: CivilDay, rhs: CivilDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
