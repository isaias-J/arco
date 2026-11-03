//
//  VaultPrivacyScreen.swift
//  Arco
//
//  Cobertura de privacidad de la bóveda en segundo plano (spec §17 "Privacidad
//  de la interfaz", T63): "Salir de app mostrando foto: selector de apps no
//  expone imagen".
//
//  RESPONSABILIDAD
//  ---------------
//  - VaultLock garantiza el estado LÓGICO (vuelve a "bloqueado") al pasar a
//    segundo plano. La cobertura VISUAL inmediata de la imagen en el selector de
//    apps corresponde a la capa de vistas — este modificador.
//  - Cuando `scenePhase != .active`, se superpone una vista opaca sobre cualquier
//    contenido de la bóveda Y se llama a `vaultLock.lock()`. Así la captura del
//    selector de apps no expone miniaturas ni fotos.
//  - Se distingue de un desbloqueo accidental: aquí solo se CUBRE y se bloquea;
//    no se intenta autenticar durante el cambio de escena (spec §17 [A07]).
//

import SwiftUI

/// Modificador reutilizable que cubre su contenido con una pantalla opaca
/// cuando la escena no está activa, y bloquea la bóveda (T63).
struct VaultPrivacyScreen: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .overlay {
                // Cobertura opaca cuando la escena no está activa (inactive o
                // background): tapa cualquier foto antes de la captura del
                // selector de apps.
                if scenePhase != .active {
                    privacyCover
                        .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    // Estado lógico a bloqueado en cuanto deja de estar activa.
                    appState.vaultLock.lock()
                }
            }
    }

    /// Cubierta opaca con la identidad de la app (no transparente: no debe
    /// dejar ver el contenido debajo en la captura del selector).
    private var privacyCover: some View {
        ZStack {
            ArcoColor.background
                .ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(ArcoColor.brand)
                Text("Bóveda protegida")
                    .font(.headline)
                    .foregroundStyle(ArcoColor.textPrimary)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Aplica la cobertura de privacidad de la bóveda (T63). Debe usarse en
    /// cualquier vista que muestre contenido privado desbloqueado.
    func vaultPrivacyScreen() -> some View {
        modifier(VaultPrivacyScreen())
    }
}
