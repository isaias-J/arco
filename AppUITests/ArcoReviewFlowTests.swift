import XCTest

/// Recorridos de la segunda revisión independiente: gráficas históricas, guía de poses y
/// restauración (exportar y volver a importar con el selector de Archivos del sistema).
/// Solo con datos de prueba, en el simulador aislado.
final class ArcoReviewFlowTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func freshApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-arco-uitest-reset"] + extra
        app.launch()
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
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

    private func replace(_ field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let value = field.value as? String, !value.isEmpty, value != "—" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
        }
        field.typeText(text)
    }

    /// Registra una sesión con un ejercicio buscado y series (peso, reps), y la finaliza.
    private func logSession(_ app: XCUIApplication, search text: String, sets: [(String, String)]) {
        app.buttons["today.start"].tap()
        let preloaded = app.staticTexts["Tu selección (1)"]
        if !preloaded.waitForExistence(timeout: 2) {
            let search = app.buttons["selection.search"]
            scrollTo(search, in: app)
            search.tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(text)
            app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.tap()
        }
        app.buttons["selection.start"].tap()
        for (i, set) in sets.enumerated() {
            if i > 0 { app.buttons["session.addSet"].firstMatch.tap() }
            let w = app.textFields.matching(identifier: "set.weight").element(boundBy: 0)
            XCTAssertTrue(w.waitForExistence(timeout: 5))
            replace(w, with: set.0)
            replace(app.textFields.matching(identifier: "set.reps").element(boundBy: 0), with: set.1)
            app.buttons.matching(identifier: "set.confirm").element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons.matching(identifier: "set.completed").element(boundBy: i).waitForExistence(timeout: 5))
        }
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 5))
        app.buttons["summary.done"].tap()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 5))
    }

    // MARK: Gráficas

    /// Curva de series por músculo: periodos, método visible y tabla con los conteos reales.
    func testMuscleHistory() {
        let app = freshApp()
        logSession(app, search: "Press militar", sets: [("30", "8"), ("30", "8")])
        app.tabBars.buttons["Progreso"].tap()
        let link = app.buttons["progress.muscleHistory"]
        scrollTo(link, in: app)
        link.tap()
        app.buttons["muscleHistory.group"].firstMatch.tap()
        app.buttons["Hombros"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["muscleHistory.chart"].waitForExistence(timeout: 5) || app.images["muscleHistory.chart"].exists)
        shot(app, "30-series-musculo-semanas")
        let table = app.buttons["Ver como tabla"].firstMatch
        scrollTo(table, in: app)
        table.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'D 2 · I 0'")).firstMatch.waitForExistence(timeout: 3),
                      "Dos series de press militar: 2 directas de hombro (unión de subregiones)")
        app.swipeDown(); app.swipeDown()
        app.buttons["Meses"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'incompleto'")).firstMatch.waitForExistence(timeout: 3), "El periodo en curso se marca incompleto")
        shot(app, "31-series-musculo-meses")
    }

    /// Repeticiones por sesión de un ejercicio, con la carga asociada.
    func testRepsHistory() {
        let app = freshApp()
        logSession(app, search: "Extensión de cuádriceps", sets: [("40", "12"), ("40", "10")])
        app.tabBars.buttons["Progreso"].tap()
        let link = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Extensión de cuádriceps'")).firstMatch
        scrollTo(link, in: app)
        link.tap()
        let card = app.otherElements["exercise.reps"]
        let chart = app.otherElements["exercise.reps.chart"]
        scrollTo(chart, in: app)
        XCTAssertTrue(chart.exists || card.exists, "Debe existir la gráfica de repeticiones")
        shot(app, "32-repeticiones")
        let table = app.buttons.matching(NSPredicate(format: "label == 'Ver como tabla'")).element(boundBy: 1)
        scrollTo(table, in: app)
        if table.exists { table.tap() }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '12 rep. a 40'")).firstMatch.waitForExistence(timeout: 3),
                      "La mejor serie de la sesión a 40 kg tiene 12 repeticiones")
    }

    /// Mismas pantallas con tema oscuro y texto muy grande.
    func testHistoryDarkLargeText() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        let app = freshApp(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        app.tabBars.buttons["Progreso"].tap()
        let link = app.buttons["progress.muscleHistory"]
        scrollTo(link, in: app)
        XCTAssertTrue(link.isHittable)
        link.tap()
        XCTAssertTrue(app.otherElements["muscleHistory.empty"].waitForExistence(timeout: 5) || app.staticTexts["Aún no hay series registradas"].exists,
                      "Sin registros se explica, sin gráfica de ceros")
        shot(app, "33-series-musculo-oscuro-grande")
    }

    // MARK: Poses

    func testPoseGuide() {
        let app = freshApp()
        app.tabBars.buttons["Fotos"].tap()
        app.buttons["Crear PIN de la bóveda"].tap()
        let pin = app.secureTextFields["PIN"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap(); pin.typeText("4821")
        let confirm = app.secureTextFields["Confirmar PIN"]
        confirm.tap(); confirm.typeText("4821")
        app.buttons["Guardar"].tap()
        let field = app.secureTextFields["PIN de 4 dígitos"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("4821")
        app.buttons["Desbloquear"].tap()
        let take = app.buttons["Tomar fotos"].firstMatch
        XCTAssertTrue(take.waitForExistence(timeout: 5))
        take.tap()
        let guide = app.buttons["revision.poseGuide"]
        scrollTo(guide, in: app)
        shot(app, "34-revision-poses")
        guide.tap()
        XCTAssertTrue(app.staticTexts["Frontal relajado · base"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Brazos relajados a los lados'")).firstMatch.exists)
        shot(app, "35-guia-poses")
        app.swipeUp()
        shot(app, "36-guia-poses-biceps")
    }

    // MARK: Restauración

    private func tapSystemButton(_ app: XCUIApplication, _ labels: [String], timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "label IN %@", labels)
        let button = app.buttons.matching(predicate).firstMatch
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return true
    }

    /// Exporta una copia, la restaura sobre los mismos datos y comprueba que la previsión y el
    /// resultado lo cuentan con honestidad, que reemplazar pide confirmación y que una
    /// contraseña incorrecta no cambia nada.
    func testExportAndRestoreReport() throws {
        let app = freshApp()
        logSession(app, search: "Curl martillo", sets: [("14", "10")])
        app.tabBars.buttons["Perfil"].tap()
        let link = app.buttons["Copia de seguridad"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        link.tap()
        let pw = app.secureTextFields["backup.password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5))
        pw.tap(); pw.typeText("prueba-segura-1")
        let pw2 = app.secureTextFields["backup.confirm"]
        pw2.tap(); pw2.typeText("prueba-segura-1")
        app.buttons["backup.export"].tap()
        // Selector de Archivos del sistema: guardar en "En mi iPhone".
        guard tapSystemButton(app, ["Guardar", "Save", "Mover", "Move"], timeout: 10) else {
            throw XCTSkip("El selector de Archivos del sistema no apareció en este simulador")
        }
        // Si quedó un archivo con el mismo nombre de una ejecución anterior, se sustituye.
        _ = tapSystemButton(app, ["Reemplazar", "Replace", "Sustituir"], timeout: 3)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Copia cifrada exportada'")).firstMatch.waitForExistence(timeout: 10))

        // Después de exportar, se abre una sesión nueva con borradores sin confirmar: solo existe aquí.
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Al exportar se cierra el teclado")
        app.tabBars.buttons["Hoy"].tap()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 5))
        app.buttons["today.start"].tap()
        XCTAssertTrue(app.staticTexts["Tu selección (1)"].waitForExistence(timeout: 5))
        app.buttons["selection.start"].tap()
        XCTAssertTrue(app.textFields.matching(identifier: "set.weight").firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Perfil"].tap()

        // Contraseña incorrecta: no se modifica nada.
        let restore = app.buttons["backup.restore"]
        scrollTo(restore, in: app)
        restore.tap()
        let file = app.cells.containing(NSPredicate(format: "label CONTAINS 'Arco-'")).firstMatch
        let fileAlt = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Arco-'")).firstMatch
        if file.waitForExistence(timeout: 8) { file.tap() } else if fileAlt.waitForExistence(timeout: 4) { fileAlt.tap() } else {
            throw XCTSkip("No se pudo localizar el archivo exportado en el selector del sistema")
        }
        let prompt = app.secureTextFields["Contraseña"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        prompt.typeText("otra-contraseña")
        app.buttons["Revisar archivo"].tap()
        XCTAssertTrue(app.staticTexts["Contraseña incorrecta. No se modificó ningún dato."].waitForExistence(timeout: 15))

        // Contraseña correcta: previsión honesta y confirmación al reemplazar.
        scrollTo(restore, in: app)
        restore.tap()
        if file.waitForExistence(timeout: 8) { file.tap() } else { fileAlt.tap() }
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        prompt.typeText("prueba-segura-1")
        app.buttons["Revisar archivo"].tap()
        XCTAssertTrue(app.buttons["restore.confirm"].waitForExistence(timeout: 20))
        let unchanged = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Ya están aquí sin cambios'")).firstMatch
        for _ in 0..<6 where !unchanged.exists { app.swipeUp() }
        XCTAssertTrue(unchanged.exists, "Sobre los mismos datos, la previsión dice que ya están")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Se añadirán'")).firstMatch.exists, "No promete añadir lo que ya existe")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'ELIMINARÁN'")).firstMatch.exists, "Combinar no elimina nada")
        let keptHere = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Solo están en este iPhone y se conservan' AND label CONTAINS 'borradores sin realizar'")).firstMatch
        shot(app, "37-restaurar-prevision")
        XCTAssertTrue(keptHere.exists, "La sesión abierta y sus borradores se conservan al combinar")
        let replaceOption = app.buttons["Reemplazar con la copia"]
        for _ in 0..<4 where !replaceOption.isHittable { app.swipeDown() }
        replaceOption.tap()
        let removal = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Se ELIMINARÁN de este iPhone: 1 sesiones' AND label CONTAINS 'borradores sin realizar'")).firstMatch
        for _ in 0..<6 where !removal.exists { app.swipeUp() }
        XCTAssertTrue(removal.exists, "Reemplazar anuncia que elimina la sesión abierta y sus borradores")
        shot(app, "37b-restaurar-prevision-reemplazo")
        app.buttons["restore.confirm"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Reemplazar pide una segunda confirmación")
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS 'borradores sin realizar'")).firstMatch.exists, "La confirmación enumera los borradores")
        shot(app, "38-restaurar-reemplazo-confirmacion")
        alert.buttons["Cancelar"].tap()
        let mergeOption = app.buttons["Combinar (recomendado)"]
        for _ in 0..<6 where !mergeOption.isHittable { app.swipeDown() }
        mergeOption.tap()
        app.buttons["restore.confirm"].tap()
        let message = app.staticTexts["backup.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertTrue(message.label.hasPrefix("Restauración terminada."), message.label)
        XCTAssertTrue(message.label.contains("No había registros nuevos"), message.label)
        XCTAssertTrue(message.label.contains("Conservado lo que solo estaba aquí"), message.label)
        XCTAssertFalse(message.label.contains("Eliminado"), message.label)
        shot(app, "39-restaurar-resultado")
        // La sesión abierta sigue ahí para reanudarla.
        app.tabBars.buttons["Hoy"].tap()
        XCTAssertTrue(app.textFields.matching(identifier: "set.weight").firstMatch.waitForExistence(timeout: 5) || app.buttons["Reanudar entrenamiento"].waitForExistence(timeout: 5))
    }
}
