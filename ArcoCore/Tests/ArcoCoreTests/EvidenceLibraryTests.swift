import Testing
import Foundation
@testable import ArcoCore

@Suite("Biblioteca de fuentes (spec §9, §24)")
struct EvidenceLibraryTests {
    @Test func librarySourcesAreCompleteAndWellFormed() {
        let all = EvidenceLibrary.all
        #expect(all.count == 29)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(EvidenceLibrary.sources(of: .training).count == 13)
        #expect(EvidenceLibrary.sources(of: .bmi).count == 3)
        #expect(EvidenceLibrary.sources(of: .apple).count == 13)
        for s in all {
            #expect(s.url.hasPrefix("https://"), "\(s.id)")
            #expect(URL(string: s.url) != nil, "\(s.id)")
            #expect(s.additionalURLs.allSatisfy { $0.hasPrefix("https://") }, "\(s.id)")
            #expect(!s.title.isEmpty && !s.scope.isEmpty, "\(s.id)")
            #expect(s.reviewed == "2026-11-02")
        }
        #expect(EvidenceLibrary.source("E02")?.year == 2026)
    }

    @Test func weeklySummaryPublicInitBuildsMessages() {
        let s = WeeklySummary(start: Date(), end: Date(), isPartial: true, sessions: 2, workingSets: 30, previousWeekWorkingSets: 20, attendedDays: 2, plannedDays: 3, topGroups: [(.chest, 10)], streak: 2)
        #expect(s.messages.first == "2 sesiones y 30 series de trabajo hasta hoy.")
        #expect(s.messages.contains("Asistencia: 2 de 3 días planificados transcurridos."))
    }
}
