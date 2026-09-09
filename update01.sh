#!/usr/bin/env bash

# ==============================================================================
# SCRIPT DE MANTENIMIENTO PARA UBUNTU SERVER
# ==============================================================================

# 1. Comprobación de privilegios de ejecución
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[31m[ERROR] Ejecuta este script con privilegios de root (sudo).\e[0m"
    exit 1
fi

# 2. Configuración y utilidades
LOG_FILE="/var/log/mantenimiento_servidor.log"

log() {
    local nivel="$1"
    shift
    local mensaje="$*"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Registro persistente en el archivo
    echo "[$timestamp] [$nivel] $mensaje" >> "$LOG_FILE"

    # Salida visual por terminal con formato de color
    case "$nivel" in
        "INFO")  echo -e "\e[34m[$nivel]\e[0m $mensaje" ;;
        "OK")    echo -e "\e[32m[$nivel]\e[0m $mensaje" ;;
        "WARN")  echo -e "\e[33m[$nivel]\e[0m $mensaje" ;;
        "ERROR") echo -e "\e[31m[$nivel]\e[0m $mensaje" ;;
    esac
}

log "INFO" "================ INICIO DE MANTENIMIENTO ================"

# 3. Actualización del Sistema Base (APT)
log "INFO" ">> [1/5] Actualizando repositorios e índices de paquetes..."
export DEBIAN_FRONTEND=noninteractive

if apt update >> "$LOG_FILE" 2>&1; then
    log "INFO" "Aplicando actualizaciones de paquetes instalados..."
    apt upgrade -y >> "$LOG_FILE" 2>&1
    apt autoremove --purge -y >> "$LOG_FILE" 2>&1
    apt autoclean -y >> "$LOG_FILE" 2>&1
    apt clean >> "$LOG_FILE" 2>&1
    log "OK" "Mantenimiento de paquetes APT finalizado."
else
    log "ERROR" "Falló 'apt update'. Se omite la actualización de paquetes para evitar inconsistencias."
fi

# 4. Limpieza de Revisiones de Snap (si está instalado)
if command -v snap >/dev/null 2>&1; then
    log "INFO" ">> [2/5] Optimizando paquetes Snap..."
    snap refresh >> "$LOG_FILE" 2>&1
    snap list --all | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
        log "INFO" "Eliminando revisión inactiva: $snapname (rev $revision)"
        snap remove "$snapname" --revision="$revision" >> "$LOG_FILE" 2>&1
    done
    log "OK" "Limpieza de Snap completada."
fi

# 5. Limpieza de Logs de Systemd (Journald)
log "INFO" ">> [3/5] Purgando registros antiguos de journald (>14 días)..."
journalctl --vacuum-time=14d >> "$LOG_FILE" 2>&1
log "OK" "Logs de systemd depurados."

# 6. Limpieza de Archivos Temporales Antiguos
log "INFO" ">> [4/5] Depurando archivos temporales en /tmp y /var/tmp (>48h)..."
find /tmp -mindepth 1 -type f -atime +2 -delete 2>/dev/null
find /var/tmp -mindepth 1 -type f -atime +2 -delete 2>/dev/null
log "OK" "Limpieza de temporales completada."

# 7. Diagnóstico de Servicios y Necesidad de Reinicio
log "INFO" ">> [5/5] Comprobando salud del sistema..."
FAILED_SERVICES=$(systemctl list-units --state=failed --no-legend --plain)

if [ -n "$FAILED_SERVICES" ]; then
    log "ERROR" "Se detectaron servicios fallidos en systemd:"
    echo "$FAILED_SERVICES" | tee -a "$LOG_FILE"
else
    log "OK" "Todos los servicios de systemd funcionan correctamente."
fi

if [ -f /var/run/reboot-required ]; then
    log "WARN" "El servidor requiere un reinicio por actualización de kernel/librerías."
    cat /var/run/reboot-required.pkgs 2>/dev/null >> "$LOG_FILE"
else
    log "OK" "No se requiere reinicio del servidor."
fi

log "INFO" "================ FIN DE MANTENIMIENTO ================"