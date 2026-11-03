import XCTest

/// Recorridos de las etapas de cierre (SEGUIMIENTO/08-ETAPAS.md), en el simulador aislado.
final class ArcoStageFlowTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func freshApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-arco-uitest-reset"]
        app.launch()
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 5))
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, max: Int = 10) {
        for _ in 0..<max where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    /// Empieza una sesión con el ejercicio buscado y registra series (peso, reps).
    private func logSession(_ app: XCUIApplication, search text: String, label: String, sets: [(String, String)], finish: Bool = true) {
        app.buttons["today.start"].tap()
        let search = app.buttons["selection.search"]
        scrollTo(search, in: app)
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(text)
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", label)).firstMatch.tap()
        app.buttons["selection.start"].tap()
        for (i, set) in sets.enumerated() {
            if i > 0 { app.buttons["session.addSet"].firstMatch.tap() }
            // Las series confirmadas se muestran como texto: el único campo editable es el borrador nuevo.
            let w = app.textFields.matching(identifier: "set.weight").element(boundBy: 0)
            XCTAssertTrue(w.waitForExistence(timeout: 5))
            replace(w, with: set.0)
            let r = app.textFields.matching(identifier: "set.reps").element(boundBy: 0)
            replace(r, with: set.1)
            app.buttons.matching(identifier: "set.confirm").element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons.matching(identifier: "set.completed").element(boundBy: i).waitForExistence(timeout: 5))
        }
        if finish {
            app.buttons["session.finish"].tap()
            XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 5))
            app.buttons["summary.done"].tap()
            XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 5))
        }
    }

    /// Escribe `text` en un campo dejando solo ese valor (borra lo precargado desde el final).
    private func replace(_ field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        clear(field)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "El campo debe contener exactamente lo escrito")
    }

    private func clear(_ field: XCUIElement) {
        guard let value = field.value as? String, !value.isEmpty, value != "—" else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
    }

    /// Deja el día de hoy como entrenamiento que incluye `group` (la prueba no depende del día real).
    private func planToday(including group: String, _ app: XCUIApplication) {
        app.buttons["today.routine.edit"].tap()
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        let rest = app.switches["routine.rest.\(weekday)"]
        scrollTo(rest, in: app)
        XCTAssertTrue(rest.exists)
        if (rest.value as? String) == "1" {
            rest.switches.firstMatch.exists ? rest.switches.firstMatch.tap() : rest.tap()
        }
        let button = app.buttons["routine.group.\(weekday).\(group)"]
        scrollTo(button, in: app)
        XCTAssertTrue(button.exists)
        if !button.isSelected { button.tap() }
        app.buttons["routine.save"].tap()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 5))
    }

    /// §11.4: tras trabajar hombro anterior, la siguiente selección explica y propone lateral/posterior.
    func testSuggestionAfterAnteriorShoulderWork() {
        let app = freshApp()
        planToday(including: "shoulders", app)
        logSession(app, search: "Press militar", label: "Press militar", sets: [("30", "8"), ("30", "8")])
        app.buttons["today.start"].tap()
        let card = app.staticTexts["Prioridad posible: Deltoides lateral"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Debe aparecer una sugerencia de énfasis explicada")
        let why = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Deltoides anterior: 2 series directas'")).firstMatch
        XCTAssertTrue(why.exists, "La explicación cita las series que la originan")
        XCTAssertTrue(app.staticTexts["Prioridad posible: Deltoides posterior"].exists)
        shot(app, "20-sugerencia")
        let keep = app.buttons["Mantener mi elección"].firstMatch
        keep.tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2), "Rechazar la sugerencia la oculta")
        XCTAssertTrue(app.staticTexts["Prioridad posible: Deltoides posterior"].exists, "Solo se oculta la sugerencia rechazada")
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Elevaciones laterales (añadido)'")).firstMatch.exists, "Rechazar no cambia la selección")
    }

    /// Catálogo: renombrar y archivar sin perder historial; el archivado no se ofrece al elegir.
    func testCatalogRenameAndArchive() {
        let app = freshApp()
        logSession(app, search: "Curl martillo", label: "Curl martillo", sets: [("14", "10")])
        app.buttons["today.catalog"].tap()
        let search = app.textFields["catalog.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("martillo")
        app.buttons["catalog.exercise.curl_hammer"].tap()
        let name = app.textFields["catalog.detail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replace(name, with: "Martillo en cuerda")
        app.buttons["Guardar nombre"].tap()
        XCTAssertTrue(app.staticTexts["Nombre guardado."].waitForExistence(timeout: 5))
        let archive = app.buttons["catalog.detail.archive"]
        scrollTo(archive, in: app)
        archive.tap()
        app.buttons["Archivar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["catalog.detail.unarchive"].waitForExistence(timeout: 5))
        shot(app, "21-catalogo-archivado")

        // El historial sigue con el nombre nuevo en Progreso.
        app.tabBars.buttons["Progreso"].tap()
        let link = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Martillo en cuerda'")).firstMatch
        scrollTo(link, in: app)
        XCTAssertTrue(link.exists, "El historial se conserva bajo el nombre nuevo")

        // No se ofrece al elegir ejercicios.
        app.tabBars.buttons["Hoy"].tap()
        for _ in 0..<3 where !app.buttons["today.start"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.buttons["today.start"].tap()
        let search2 = app.buttons["selection.search"]
        scrollTo(search2, in: app)
        search2.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Martillo")
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Martillo en cuerda'")).firstMatch.waitForExistence(timeout: 2))
    }

    /// Rutina editable: marcar hoy como descanso se refleja en Hoy y en Asistencia.
    func testRoutineEditAppliesFromToday() {
        let app = freshApp()
        app.buttons["today.routine.edit"].tap()
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        let rest = app.switches["routine.rest.\(weekday)"]
        scrollTo(rest, in: app)
        XCTAssertTrue(rest.exists)
        let isRest = (rest.value as? String) == "1"
        rest.switches.firstMatch.exists ? rest.switches.firstMatch.tap() : rest.tap()
        if isRest {
            // Hoy era descanso: al quitarlo hay que elegir un grupo.
            let group = app.buttons["routine.group.\(weekday).legs"]
            scrollTo(group, in: app)
            group.tap()
        }
        app.buttons["routine.save"].tap()
        let routine = app.staticTexts["today.routine"]
        XCTAssertTrue(routine.waitForExistence(timeout: 5))
        if isRest {
            XCTAssertNotEqual(routine.label, "Descanso planificado")
        } else {
            XCTAssertEqual(routine.label, "Descanso planificado")
        }
        shot(app, "22-rutina-editada")
    }

    /// Sesión: sustituir un ejercicio sin series y reordenar.
    func testSubstituteInSession() {
        let app = freshApp()
        app.buttons["today.start"].tap()
        let search = app.buttons["selection.search"]
        scrollTo(search, in: app)
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Peck deck de pecho")
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Peck deck de pecho'")).firstMatch.tap()
        app.buttons["selection.start"].tap()
        let menu = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Opciones de'")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["Sustituir por…"].tap()
        let f2 = app.searchFields.firstMatch
        XCTAssertTrue(f2.waitForExistence(timeout: 5))
        f2.tap(); f2.typeText("Press de pecho en máquina")
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Press de pecho en máquina'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Press de pecho en máquina"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Peck deck de pecho"].exists)
        shot(app, "23-sustituido")
    }

    /// Doble progresión: con la regla cumplida, la siguiente sesión lo dice sin cambiar pesos.
    func testDoubleProgressionMessage() {
        let app = freshApp()
        logSession(app, search: "Extensión de cuádriceps", label: "Extensión de cuádriceps", sets: [("40", "12"), ("40", "12")])
        app.buttons["today.catalog"].tap()
        let search = app.textFields["catalog.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Extensión de cuádriceps")
        app.buttons["catalog.exercise.legs_extension"].tap()
        let toggle = app.switches["catalog.detail.progression"]
        scrollTo(toggle, in: app)
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        for (id, value) in [("progression.lower", "8"), ("progression.upper", "12"), ("progression.referenceSets", "2"), ("progression.increment", "2")] {
            let f = app.textFields[id]
            scrollTo(f, in: app)
            XCTAssertTrue(f.exists, "Falta el campo \(id)")
            // El elemento accesible abarca la fila; el campo editable está a la derecha.
            f.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            f.typeText(value)
        }
        let save = app.buttons["catalog.detail.progression.save"]
        scrollTo(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["Regla guardada."].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["today.start"].tap()
        // La selección parte de la última sesión del mismo día de rutina (spec §8); si no, se busca.
        let preloaded = app.staticTexts["Tu selección (1)"]
        if !preloaded.waitForExistence(timeout: 3) {
            let s = app.buttons["selection.search"]
            scrollTo(s, in: app)
            s.tap()
            let f = app.searchFields.firstMatch
            XCTAssertTrue(f.waitForExistence(timeout: 5))
            f.tap(); f.typeText("Extensión de cuádriceps")
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Extensión de cuádriceps'")).firstMatch.tap()
        }
        app.buttons["selection.start"].tap()
        let message = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Cumpliste tu regla para considerar subir'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '40×12, 40×12'")).firstMatch.exists, "La referencia anterior muestra las dos series tal como se registraron")
        let weight = app.textFields["set.weight"].firstMatch
        XCTAssertEqual(weight.value as? String, "40", "La regla no cambia pesos por sí sola")
        shot(app, "24-doble-progresion")
    }

    /// §2: la fecha de inicio de entrenamiento se pide en la configuración (opcional) y queda editable.
    func testTrainingStartAskedInOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-arco-uitest-reset"]
        app.launch()
        let toggle = app.switches["onboarding.trainingStart"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0", "No se inventa la fecha: empieza sin indicar")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 3) || app.buttons.containing(NSPredicate(format: "label CONTAINS 'Empecé a entrenar'")).firstMatch.exists)
        app.buttons["onboarding.start"].tap()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Perfil"].tap()
        let personal = app.buttons["profile.personal"]
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        personal.tap()
        let weeks = app.staticTexts["Tiempo entrenando"]
        scrollTo(weeks, in: app)
        XCTAssertTrue(weeks.exists, "La fecha indicada se conserva y se puede editar en Datos personales")
        shot(app, "26-inicio-entrenamiento")
    }

    /// Biblioteca de fuentes y resumen semanal visibles en Progreso.
    func testEvidenceAndSummary() {
        let app = freshApp()
        app.tabBars.buttons["Progreso"].tap()
        XCTAssertTrue(app.otherElements["progress.weekSummary"].waitForExistence(timeout: 5) || app.staticTexts["Resumen semanal"].waitForExistence(timeout: 5))
        let link = app.buttons["progress.evidence"]
        scrollTo(link, in: app)
        link.tap()
        XCTAssertTrue(app.staticTexts["Método fraccional"].waitForExistence(timeout: 5))
        let e02 = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'The Resistance Training Dose Response'")).firstMatch
        scrollTo(e02, in: app)
        XCTAssertTrue(e02.exists)
        shot(app, "25-fuentes")
    }
}
