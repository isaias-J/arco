import SwiftUI
import ArcoCore

/// Sección Fotos (spec §16, §17): bóveda privada bloqueada. Muestra estado bloqueado sin
/// miniaturas hasta autenticar con PIN o Face ID. Todas las rutas pasan por el mismo control.
struct PhotosView: View {
    @Environment(AppState.self) private var appState
    @State private var pinInput = ""
    @State private var showPINError = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.vaultLock.isUnlocked {
                    VaultGalleryView()
                } else {
                    lockedState
                }
            }
            .navigationTitle("Fotos")
            .background(ArcoColor.background)
        }
    }

    private var lockedState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(ArcoColor.brand)
            Text("Bóveda privada")
                .font(.title2.bold())
            Text("Tus fotos se guardan cifradas en este dispositivo, fuera de Apple Fotos. Desbloquea para verlas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            if appState.vaultLock.isPINConfigured {
                SecureField("PIN de 4 dígitos", text: $pinInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .multilineTextAlignment(.center)
                Button("Desbloquear") {
                    if appState.vaultLock.unlockWithPIN(pinInput) {
                        pinInput = ""
                    } else {
                        showPINError = true
                    }
                }
                .buttonStyle(.borderedProminent)

                if appState.vaultLock.canUseBiometrics {
                    Button {
                        Task { _ = await appState.vaultLock.unlockWithBiometrics() }
                    } label: {
                        Label("Usar Face ID", systemImage: "faceid")
                    }
                }
            } else {
                NavigationLink("Crear PIN de la bóveda") {
                    PINSetupView()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.xl)
        .alert("PIN incorrecto", isPresented: $showPINError) {
            Button("Entendido", role: .cancel) {}
        }
    }
}

/// Galería desbloqueada: muestra la cuadrícula de check-ins con navegación a
/// captura, comparación y secuencia (spec §16). Mantiene "Bloquear ahora" y
/// aplica la cobertura de privacidad en segundo plano (T63).
struct VaultGalleryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        PhotoGalleryGridView()
            .toolbar {
                // Se conserva el control de bloqueo manual (spec §17).
                ToolbarItem(placement: .topBarLeading) {
                    Button("Bloquear ahora") { appState.vaultLock.lock() }
                        .accessibilityHint("Bloquea la bóveda y oculta las fotos")
                }
            }
            // Cobertura de privacidad del selector de apps y bloqueo en 2.º plano (T63).
            .vaultPrivacyScreen()
    }
}

struct PINSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirm = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Elige un PIN de 4 dígitos") {
                SecureField("PIN", text: $pin).keyboardType(.numberPad)
                SecureField("Confirmar PIN", text: $confirm).keyboardType(.numberPad)
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
            }
        }
    }

    private func save() {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else {
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
