#!/bin/zsh
# Revisión previa a publicar en el repositorio PÚBLICO. Analiza exactamente lo que va a
# subirse (el índice de git) y falla si encuentra secretos, datos privados o artefactos.
# Uso: scripts/preflight-publico.sh   (desde la raíz del repositorio)
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
fail=0
staged=$(git ls-files)

echo "1) Artefactos y datos que nunca deben publicarse"
bad=$(print -l $staged | grep -E '(^|/)(\.build|build|DerivedData|xcuserdata)/|\.DS_Store$|\.(store|store-wal|store-shm|sqlite|arcobk|p12|pem|key|cer|mobileprovision|ips|tgz|zip)$|(^|/)\.env|referencias/')
if [[ -n "$bad" ]]; then echo "$bad"; fail=1; else echo "   ok"; fi

echo "2) Patrones de secretos"
hits=$(git grep -nIE 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_|gho_[A-Za-z0-9]{20,}|xox[baprs]-|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY|Bearer [A-Za-z0-9._-]{20,}' -- . ':!scripts/preflight-publico.sh')
if [[ -n "$hits" ]]; then echo "$hits"; fail=1; else echo "   ok"; fi

echo "3) Rutas locales y equipo de firma"
hits=$(git grep -nIE '/Users/[A-Za-z]|DEVELOPMENT_TEAM = [A-Z0-9]{10}' -- . ':!scripts/preflight-publico.sh')
if [[ -n "$hits" ]]; then echo "$hits"; fail=1; else echo "   ok"; fi

echo "4) Contraseñas literales fuera de las pruebas"
hits=$(git grep -nIE 'password: *"[^"]+"' -- . ':!ArcoCore/Tests' ':!scripts/preflight-publico.sh')
if [[ -n "$hits" ]]; then echo "$hits"; fail=1; else echo "   ok"; fi

echo "5) Registros que podrían filtrar datos (print/NSLog/os_log en la app)"
hits=$(git grep -nIE '\bprint\(|NSLog\(|os_log\(|debugPrint\(' -- App ArcoCore/Sources)
if [[ -n "$hits" ]]; then echo "$hits"; fail=1; else echo "   ok"; fi

if (( fail )); then echo "\n✘ NO publicar: revisa los puntos anteriores."; exit 1; fi
echo "\n✔ Sin hallazgos. Recuerda: el correo del autor de cada commit es público."
