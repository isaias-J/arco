import Foundation

/// Estimación de fuerza máxima (e1RM) usando Epley, como decisión conservadora (spec §12, E13).
/// Es una estimación secundaria, etiquetada; NO sustituye el registro ni es "1RM real".
public enum EstimatedOneRM {

    /// Epley: carga × (1 + reps/30). Se produce SOLO si se cumplen todos los filtros (spec §12):
    /// - 2 a 10 repeticiones.
    /// - carga externa positiva (no asistencia, no peso corporal, convención definida).
    /// - RIR declarado 0 o 1.
    /// Para una repetición real se usa la carga observada (no Epley).
    /// Devuelve nil si no es elegible: no se fuerza el indicador.
    public static func epley(load: Load, reps: Int, rir: RIR?) -> Decimal? {
        // Convención elegible: externalTotal, perDumbbell o machineNominal (etiquetado como
        // índice de esa máquina). Asistencia, peso corporal y "none" quedan fuera.
        switch load.convention {
        case .externalTotal, .perDumbbell, .machineNominal:
            break
        case .assistance, .bodyweight, .none:
            return nil
        }
        guard let kg = load.kilograms, kg > 0 else { return nil }

        // Una repetición real: carga observada (no fórmula).
        if reps == 1 {
            // Solo si RIR 0 (realmente al límite). RIR desconocido o >0: no producir.
            if rir?.exactValue == 0 { return kg }
            return nil
        }

        // Rango 2–10 reps.
        guard reps >= 2 && reps <= 10 else { return nil }

        // RIR declarado 0 o 1.
        guard let r = rir?.exactValue, r == 0 || r == 1 else { return nil }

        let factor = Decimal(1) + Decimal(reps) / Decimal(30)
        return kg * factor
    }
}
