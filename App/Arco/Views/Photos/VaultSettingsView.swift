import SwiftUI
import ArcoCore

/// Ajustes de la bóveda de fotos (spec §17): Face ID opcional, cambio de PIN, bloqueo manual
/// y explicación del modelo de protección. Solo se llega aquí con la bóveda desbloqueada.
struct VaultSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var currentPIN = ""
    @State private var pinMessage: String?
    @State private var showPINSetup = false
    /// Copia local de la preferencia: `useFaceID` vive en UserDefaults y no es observable.
    @State private var faceIDEnabled = false

    var body: some View {
        Form {
            faceIDSection
            changePINSection
            Section {
                Button("Bloquear ahora", role: .destructive) { appState.vaultLock.lock() }
                    .accessibilityHint("Bloquea la bóveda y oculta las fotos")
            }
            protectionSection
        }
        .navigationTitle("Bóveda de fotos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { faceIDEnabled = appState.useFaceID }
        .onChange(of: faceIDEnabled) { _, value in appState.useFaceID = value }
        .sheet(isPresented: $showPINSetup, onDismiss: { currentPIN = "" }) {
            NavigationStack { PINSetupView() }
        }
    }

    // MARK: Face ID

    private var faceIDSection: some View {
        let available = appState.vaultLock.canUseBiometrics
        return Section {
            Toggle("Desbloquear con Face ID", isOn: $faceIDEnabled)
                .disabled(!available)
        } header: {
            Text("Face ID")
        } footer: {
            if available {
                Text("Es opcional. Si Face ID se cancela o falla, la bóveda sigue bloqueada y puedes usar tu PIN.")
            } else {
                Text("Face ID o Touch ID no está disponible o no está configurado en este dispositivo. Puedes activarlo en Ajustes de iOS; mientras tanto, la bóveda se abre con tu PIN.")
            }
        }
    }

    // MARK: Cambiar PIN

    private var changePINSection: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let remaining = Int(appState.vaultLock.lockoutRemaining.rounded(.up))
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SecureField("PIN actual", text: $currentPIN)
                        .keyboardType(.numberPad)
                        .disabled(remaining > 0)
                        .onChange(of: currentPIN) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(4))
                            if digits != value { currentPIN = digits }
                        }
                    if remaining > 0 {
                        Text("Demasiados intentos. Espera \(remaining) s")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button("Cambiar PIN") { verifyCurrentPIN() }
                        .disabled(remaining > 0 || currentPIN.count != 4)
                }
            }
            if let pinMessage {
                Text(pinMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("PIN")
        } footer: {
            Text("Para cambiarlo, escribe primero el PIN actual. Si lo olvidaste, bloquea la bóveda y usa «Olvidé mi PIN»: iOS pedirá Face ID, Touch ID o el código del dispositivo.")
        }
    }

    private func verifyCurrentPIN() {
        if appState.vaultLock.verifyPIN(currentPIN) {
            pinMessage = nil
            showPINSetup = true
        } else {
            pinMessage = "PIN incorrecto."
            currentPIN = ""
        }
    }

    // MARK: Modelo de protección

    private var protectionSection: some View {
        Section("Cómo se protegen tus fotos") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("El PIN es una barrera de acceso dentro de Arco; no es la clave de cifrado.")
                Text("Las fotos se cifran con una clave aleatoria guardada en el llavero (Keychain) de este dispositivo, sin sincronizar.")
                Text("Las fotos no se guardan en Apple Fotos ni en iCloud y quedan excluidas de la copia de seguridad automática.")
                Text("Restablecer el PIN no borra fotos. Una reinstalación o la pérdida del iPhone no garantiza recuperarlas, salvo con una copia exportada que las incluya.")
                Text("Tus datos se guardan en este dispositivo. Para conservar una copia independiente puedes exportar un archivo cifrado.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
