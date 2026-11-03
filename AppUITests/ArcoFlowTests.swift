import XCTest

/// Recorridos de extremo a extremo en un simulador aislado. Cada prueba arranca con la base
/// local borrada (`-arco-uitest-reset`), así que no se usan ni se tocan datos reales.
/// Se usa XCTest porque la automatización de interfaz (XCUIApplication) no está en Swift Testing.
final class ArcoFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = reset ? ["-arco-uitest-reset"] : []
        app.launch()
        return app
    }

    private func completeOnboarding(_ app: XCUIApplication) {
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "El onboarding debe aparecer en la primera apertura")
        start.tap()
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// T76: la primera apertura no muestra datos de demostración como entrenamientos.
    func testFirstLaunchHasNoDemoData() {
        let app = launch()
        screenshot(app, "01-onboarding")
        completeOnboarding(app)
        XCTAssertTrue(app.staticTexts["today.routine"].waitForExistence(timeout: 5))
        screenshot(app, "02-hoy")
        app.tabBars.buttons["Progreso"].tap()
        XCTAssertTrue(app.staticTexts["Aún no hay entrenamientos"].waitForExistence(timeout: 5))
        screenshot(app, "03-progreso-vacio")
        app.tabBars.buttons["Asistencia"].tap()
        XCTAssertTrue(app.staticTexts["Todavía no hay días registrados."].waitForExistence(timeout: 5))
    }

    /// T01/T03/T34: elegir ejercicio, confirmar una serie, cerrar la app y recuperar la sesión.
    func testLogSetSurvivesRelaunch() {
        var app = launch()
        completeOnboarding(app)
        app.buttons["today.start"].tap()

        let searchButton = app.buttons["selection.search"]
        for _ in 0..<8 where !searchButton.exists || !searchButton.isHittable { app.swipeUp() }
        searchButton.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Press plano")
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Press plano con barra'")).firstMatch.tap()
        app.buttons["selection.start"].tap()

        let weight = app.textFields["set.weight"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["set.completed"].exists, "Un borrador no es una serie realizada (T01)")
        weight.tap(); weight.typeText("60")
        let reps = app.textFields["set.reps"].firstMatch
        reps.tap(); reps.typeText("8")
        app.buttons["set.confirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["set.completed"].waitForExistence(timeout: 5))
        screenshot(app, "04-serie-confirmada")

        // Cerrar y reabrir SIN borrar la base.
        app.terminate()
        app = launch(reset: false)
        let resume = app.buttons["today.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "La sesión activa debe recuperarse (T03)")
        resume.tap()
        let completed = app.buttons["set.completed"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("60"), "La carga confirmada se conserva")
        XCTAssertTrue(completed.label.contains("8 rep"), "Las repeticiones se conservan")

        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.staticTexts["Sesión finalizada"].waitForExistence(timeout: 5))
        screenshot(app, "05-resumen")
        app.buttons["summary.done"].tap()

        app.tabBars.buttons["Asistencia"].tap()
        XCTAssertTrue(app.staticTexts["Entrenamiento registrado"].waitForExistence(timeout: 5), "La primera serie de trabajo crea asistencia (T34)")
    }

    /// T15 en interfaz: "Hoy descansé" guarda la resolución y se puede deshacer.
    func testRestResolution() {
        let app = launch()
        completeOnboarding(app)
        app.tabBars.buttons["Asistencia"].tap()
        app.buttons["attendance.didRest"].tap()
        XCTAssertTrue(app.staticTexts["Descanso confirmado"].waitForExistence(timeout: 5))
        screenshot(app, "06-descanso")
        app.terminate()
        let again = launch(reset: false)
        again.tabBars.buttons["Asistencia"].tap()
        XCTAssertTrue(again.staticTexts["Descanso confirmado"].waitForExistence(timeout: 5), "El descanso persiste tras reabrir")
    }

    /// Hallazgo 11: un peso negativo no se guarda; uno válido sí y se muestra como actual.
    func testWeightValidation() {
        let app = launch()
        completeOnboarding(app)
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["Añadir pesaje"].tap()
        let field = app.textFields["Peso"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("-1")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.navigationBars["Añadir pesaje"].exists, "Un peso negativo no se acepta")
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Seleccionar todo"].exists { app.menuItems["Seleccionar todo"].tap() }
        field.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "70")
        app.buttons["Guardar"].tap()
        let notNow = app.buttons["Ahora no"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5), "Tras guardar se ofrece añadir una foto opcional")
        notNow.tap()
        XCTAssertTrue(app.staticTexts["Peso actual"].waitForExistence(timeout: 5))
        screenshot(app, "07-perfil-peso")
    }

    /// T60/T62: la bóveda se crea con PIN, un PIN erróneo no abre y el correcto sí.
    func testVaultPIN() {
        let app = launch()
        completeOnboarding(app)
        app.tabBars.buttons["Fotos"].tap()
        XCTAssertFalse(app.images.matching(identifier: "photo").firstMatch.exists)
        app.buttons["Crear PIN de la bóveda"].tap()
        let pin = app.secureTextFields["PIN"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap(); pin.typeText("4821")
        let confirm = app.secureTextFields["Confirmar PIN"]
        confirm.tap(); confirm.typeText("4821")
        app.buttons["Guardar"].tap()

        let field = app.secureTextFields["PIN de 4 dígitos"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("1111")
        app.buttons["Desbloquear"].tap()
        XCTAssertTrue(app.staticTexts["PIN incorrecto."].waitForExistence(timeout: 5))
        XCTAssertTrue(field.exists, "Con PIN incorrecto la bóveda sigue bloqueada")

        field.tap(); field.typeText("4821")
        app.buttons["Desbloquear"].tap()
        XCTAssertTrue(app.buttons["Bloquear ahora"].waitForExistence(timeout: 5))
        screenshot(app, "08-boveda-abierta")
        app.buttons["Bloquear ahora"].tap()
        XCTAssertTrue(app.secureTextFields["PIN de 4 dígitos"].waitForExistence(timeout: 5))
    }

    /// T74 (parcial): tema oscuro y texto de accesibilidad grande; las acciones esenciales
    /// siguen visibles y pulsables.
    func testDarkModeAndLargeText() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        let app = XCUIApplication()
        app.launchArguments = ["-arco-uitest-reset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        screenshot(app, "10-onboarding-oscuro-texto-grande")
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isHittable)
        start.tap()
        let begin = app.buttons["today.start"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        for _ in 0..<4 where !begin.isHittable { app.swipeUp() }
        XCTAssertTrue(begin.isHittable, "Empezar entrenamiento debe poder pulsarse con texto grande")
        screenshot(app, "11-hoy-oscuro-texto-grande")
        app.tabBars.buttons["Asistencia"].tap()
        let rest = app.buttons["attendance.didRest"]
        for _ in 0..<4 where !(rest.exists && rest.isHittable) { app.swipeUp() }
        XCTAssertTrue(rest.isHittable)
        screenshot(app, "12-asistencia-oscuro-texto-grande")
        app.tabBars.buttons["Perfil"].tap()
        screenshot(app, "13-perfil-oscuro-texto-grande")
        app.tabBars.buttons["Fotos"].tap()
        screenshot(app, "14-fotos-bloqueada-oscuro")
    }

    /// Hallazgo 1: la copia no promete fotos si la bóveda está bloqueada.
    func testBackupDescribesContentHonestly() {
        let app = launch()
        completeOnboarding(app)
        app.tabBars.buttons["Perfil"].tap()
        let link = app.buttons["Copia de seguridad"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Fotos: no'")).firstMatch.waitForExistence(timeout: 5))
        let toggle = app.switches["backup.includePhotos"]
        XCTAssertTrue(toggle.exists)
        XCTAssertFalse(toggle.isEnabled, "Sin fotos o con la bóveda bloqueada no se puede marcar 'Incluir fotos'")
        screenshot(app, "09-copia")
    }
}
