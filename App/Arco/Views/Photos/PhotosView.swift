import SwiftUI
import SwiftData
import ArcoCore

/// Sección Fotos (spec §16, §17): bóveda privada bloqueada. Muestra estado bloqueado sin
/// miniaturas hasta autenticar con PIN o Face ID. Todas las rutas a imágenes (galería,
/// detalle, comparación, secuencia, captura con superposición) cuelgan de `VaultGalleryView`,
/// que solo existe con la bóveda desbloqueada (T62).
struct PhotosView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            // Pilas de navegación distintas: al bloquear se descarta TODA la pila desbloqueada
            // (detalle, comparación, secuencia, ajustes) y sus hojas.
            if appState.vaultLock.isUnlocked {
                NavigationStack {
                    VaultGalleryView()
                }
            } else {
                NavigationStack {
                    VaultLockedView()
                        .navigationTitle("Fotos")
                        .background(ArcoBackdrop())
                }
            }
        }
        // Cubre cualquier pantalla de la pila (incluidas las empujadas) cuando la escena no
        // está activa y bloquea al pasar a segundo plano (T63).
        .vaultPrivacyScreen()
        .onChange(of: appState.selectedTab) { _, tab in
            // Al salir de la pestaña Fotos la bóveda se bloquea: no queda abierta en segundo plano.
            if tab != .photos { appState.vaultLock.lock() }
        }
    }
}

// MARK: - Estado bloqueado

/// Pantalla de desbloqueo: PIN con limitación de intentos visible (T60), Face ID opcional
/// (T61) y "Olvidé mi PIN" con autenticación del propietario del dispositivo (T64).
struct VaultLockedView: View {
    @Environment(AppState.self) private var appState

    @State private var pinInput = ""
    @State private var message: String?
    @State private var isPINConfigured = false
    @State private var showPINSetup = false
    @State private var showForgotConfirmation = false
    @State private var isAuthenticating = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(ArcoColor.brandText)
                    .frame(width: 112, height: 112)
                    .background(ArcoColor.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 32))
                    .overlay {
                        RoundedRectangle(cornerRadius: 32)
                            .strokeBorder(ArcoColor.brand.opacity(0.25), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                ArcoEyebrow(title: "Solo para ti")
                Text("Bóveda privada")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                Text("Tus fotos se guardan cifradas en este dispositivo, fuera de Apple Fotos. Desbloquea para verlas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                if isPINConfigured {
                    unlockControls
                } else {
                    Button("Crear PIN de la bóveda") { showPINSetup = true }
                        .buttonStyle(.borderedProminent)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(ArcoColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .onAppear { refreshPINState() }
        .sheet(isPresented: $showPINSetup, onDismiss: refreshPINState) {
            NavigationStack { PINSetupView() }
        }
        .alert("¿Restablecer el PIN?", isPresented: $showForgotConfirmation) {
            Button("Continuar") { Task { await recoverPIN() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("iOS te pedirá Face ID, Touch ID o el código de este dispositivo. Si lo confirmas podrás crear un PIN nuevo. Tus fotos no se pierden: la clave de cifrado está en el llavero de este dispositivo y no depende del PIN.")
        }
    }

    // MARK: Controles

    private var unlockControls: some View {
        // Refresco cada segundo para la cuenta atrás de la limitación de intentos.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = Int(appState.vaultLock.lockoutRemaining.rounded(.up))
            VStack(spacing: Spacing.lg) {
                SecureField("PIN de 4 dígitos", text: $pinInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .multilineTextAlignment(.center)
                    .disabled(remaining > 0)
                    .onSubmit(unlockWithPIN)
                    .onChange(of: pinInput) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(4))
                        if digits != value { pinInput = digits }
                    }

                if remaining > 0 {
                    Text("Demasiados intentos. Espera \(remaining) s")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Demasiados intentos. Espera \(remaining) segundos")
                }

                Button("Desbloquear", action: unlockWithPIN)
                    .buttonStyle(.borderedProminent)
                    .disabled(remaining > 0 || pinInput.count != 4)

                if appState.useFaceID && appState.vaultLock.canUseBiometrics {
                    Button {
                        Task { await unlockWithBiometrics() }
                    } label: {
                        Label("Usar Face ID", systemImage: "faceid")
                    }
                    .disabled(isAuthenticating)
                }

                Button("Olvidé mi PIN") { showForgotConfirmation = true }
                    .font(.footnote)
                    .disabled(isAuthenticating)
                    .accessibilityHint("Restablece el PIN tras autenticarte con Face ID, Touch ID o el código del dispositivo")
            }
        }
    }

    // MARK: Acciones

    private func refreshPINState() {
        isPINConfigured = appState.vaultLock.isPINConfigured
    }

    private func unlockWithPIN() {
        guard pinInput.count == 4 else { return }
        if appState.vaultLock.lockoutRemaining > 0 {
            message = nil
            return
        }
        if appState.vaultLock.unlockWithPIN(pinInput) {
            message = nil
        } else {
            message = "PIN incorrecto."
        }
        pinInput = ""
    }

    private func unlockWithBiometrics() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await appState.vaultLock.unlockWithBiometrics() {
            message = nil
        } else {
            // T61: cancelado, denegado o no disponible ⇒ sigue bloqueada.
            message = "No se desbloqueó con Face ID. La bóveda sigue bloqueada; puedes usar tu PIN."
        }
    }

    /// "Olvidé mi PIN" (T64): solo tras autenticación del propietario con el sistema.
    private func recoverPIN() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let result = await OwnerAuthentication.authenticate(reason: "Confirma que eres el propietario para restablecer el PIN de la bóveda")
        guard result == .success else {
            message = OwnerAuthentication.message(for: result)
            return
        }
        appState.vaultLock.resetPINAfterOwnerAuthentication()
        refreshPINState()
        message = "Crea un PIN nuevo. Tus fotos siguen guardadas."
        showPINSetup = true
    }
}

// MARK: - Galería desbloqueada

/// Galería desbloqueada: cuadrícula de check-ins con navegación a captura, comparación,
/// secuencia y ajustes de la bóveda (spec §16). `PhotoGalleryGridView` consume
/// `pendingPhotoWeightID` para abrir la revisión con el peso recién guardado desde Perfil.
struct VaultGalleryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        PhotoGalleryGridView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Bloquear ahora") { appState.vaultLock.lock() }
                        .accessibilityHint("Bloquea la bóveda y oculta las fotos")
                }
            }
    }
}

// MARK: - Crear / cambiar PIN

struct PINSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirm = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Elige un PIN de 4 dígitos") {
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                SecureField("Confirmar PIN", text: $confirm)
                    .keyboardType(.numberPad)
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
            Section {
                Text("El PIN protege el acceso a tus fotos dentro de la app. No es la clave de cifrado; esa la gestiona el dispositivo de forma segura.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("PIN de la bóveda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
            }
        }
    }

    private func save() {
        guard pin.count == 4, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            error = "El PIN debe tener 4 dígitos."
            return
        }
        guard pin == confirm else {
            error = "Los PIN no coinciden."
            return
        }
        do {
            try appState.vaultLock.configurePIN(pin)
            dismiss()
        } catch {
            self.error = "No se pudo guardar el PIN."
        }
    }
}
