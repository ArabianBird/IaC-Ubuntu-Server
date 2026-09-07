#!/bin/bash

# ==============================================================================
# SCRIPT DE MANTENIMIENTO PARA UBUNTU SERVER
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31m[ERROR] Ejecuta este script con privilegios de root (sudo).\e[0m"
  exit 1
fi

LOG_FILE="/var/log/mantenimiento_servidor.log"
FECHA_ACTUAL=$(date "+%Y-%m-%d %H:%M:%S")

echo "--- INICIO DE MANTENIMIENTO: $FECHA_ACTUAL ---" | tee -a "$LOG_FILE"

# 1. Actualización del Sistema Base (APT)
echo ">> [1/5] Actualizando paquetes del sistema..."
export DEBIAN_FRONTEND=noninteractive
apt update >> "$LOG_FILE" 2>&1
apt upgrade -y >> "$LOG_FILE" 2>&1
apt autoremove --purge -y >> "$LOG_FILE" 2>&1
apt autoclean -y >> "$LOG_FILE" 2>&1
apt clean >> "$LOG_FILE" 2>&1

# 2. Limpieza de Revisiones de Snap (si está instalado)
if command -v snap >/dev/null 2>&1; then
  echo ">> [2/5] Optimizando paquetes Snap..."
  snap refresh >> "$LOG_FILE" 2>&1
  snap list --all | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
    echo "Eliminando revisión antigua: $snapname (rev $revision)" >> "$LOG_FILE"
    snap remove "$snapname" --revision="$revision" >/dev/null 2>&1
  done
fi

# 3. Limpieza de Logs de Systemd (Journald)
echo ">> [3/5] Purgando registros antiguos de journald..."
journalctl --vacuum-time=14d >> "$LOG_FILE" 2>&1

# 4. Limpieza de Archivos Temporales Antiguos
echo ">> [4/5] Depurando archivos temporales en /tmp y /var/tmp..."
find /tmp -mindepth 1 -type f -atime +2 -delete 2>/dev/null
find /var/tmp -mindepth 1 -type f -atime +2 -delete 2>/dev/null

# 5. Diagnóstico de Servicios y Necesidad de Reinicio
echo ">> [5/5] Comprobando estado de servicios del servidor..."
FAILED_SERVICES=$(systemctl list-units --state=failed --no-legend --plain)

if [ -n "$FAILED_SERVICES" ]; then
  echo -e "\e[31m[ALERTA] Se detectaron servicios fallidos en systemd:\e[0m" | tee -a "$LOG_FILE"
  echo "$FAILED_SERVICES" | tee -a "$LOG_FILE"
else
  echo -e "\e[32m[OK] Todos los servicios de systemd funcionan correctamente.\e[0m"
fi

if [ -f /var/run/reboot-required ]; then
  echo -e "\e[33m[AVISO] El servidor requiere un reinicio por actualización de kernel/librerías.\e[0m" | tee -a "$LOG_FILE"
  cat /var/run/reboot-required.pkgs 2>/dev/null >> "$LOG_FILE"
else
  echo -e "\e[32m[OK] No se requiere reinicio del servidor.\e[0m"
fi

FECHA_FIN=$(date "+%Y-%m-%d %H:%M:%S")
echo "--- FIN DE MANTENIMIENTO: $FECHA_FIN ---" >> "$LOG_FILE"
