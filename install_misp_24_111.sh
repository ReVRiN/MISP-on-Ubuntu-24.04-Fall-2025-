#!/usr/bin/env bash
# ============================================================
#  MISP 2.5 Full Installation (Ubuntu 24.04)
#  Runs the official installer AS ROOT, then post-configures:
#    - BaseURL = https://192.168.1.111 <--Make whatever IP you wish
#    - Simple demo password for admin (change it!)
#  # ============================================================

set -euo pipefail

### ---- EDITABLE VARS -------------------------------------------------------
MISP_IP="192.168.1.111" # <-- Make whatever IP you wish
ADMIN_EMAIL="admin@admin.test"
ADMIN_PASS="ChangeMeNow!2025"   # <-- CHANGE THIS AFTER FIRST LOGIN
PHP_TZ="America/Toronto"        # match your environment if you like
### -------------------------------------------------------------------------

# --- Safety checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root (e.g., sudo ./install_misp_24_111.sh)."
  exit 1
fi

echo "=== [1/7] Updating system and base tools ==="
export DEBIAN_FRONTEND=noninteractive
apt update && apt -y upgrade
apt install -y curl wget git unzip software-properties-common

# (Optional) set PHP timezone early; installer will install PHP packages
if php -v >/dev/null 2>&1; then
  PHPVER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
  if [ -n "${PHPVER:-}" ] && [ -f "/etc/php/${PHPVER}/apache2/php.ini" ]; then
    sed -i "s~^;*date.timezone *=.*~date.timezone = ${PHP_TZ}~" "/etc/php/${PHPVER}/apache2/php.ini" || true
  fi
fi

echo "=== [2/7] Running official MISP 2.5 installer (root) ==="
# Important: run as root so /var/log/misp_install.log is writable
cd /tmp
rm -f INSTALL.sh
wget --no-cache -O INSTALL.sh https://raw.githubusercontent.com/MISP/MISP/2.5/INSTALL/INSTALL.ubuntu2404.sh
chmod +x INSTALL.sh
# The official script handles everything (Apache, MariaDB, PHP, Redis, HTTPS)
bash INSTALL.sh

echo "=== [3/7] Verifying core paths ==="
MISP_DIR="/var/www/MISP"
CAKE="${MISP_DIR}/app/Console/cake"
if [ ! -x "${CAKE}" ]; then
  echo "ERROR: Cake console not found at ${CAKE}. Installer may have failed."
  echo "       Check /var/log/misp_install.log for details."
  exit 2
fi

echo "=== [4/7] Setting BaseURL to https://${MISP_IP} ==="
# Use IP directly; no need to rely on misp.local
sudo -u www-data "${CAKE}" Admin setSetting "MISP.baseurl" "https://${MISP_IP}"

echo "=== [5/7] Finalize app settings (runUpdates, caches) ==="
# These are safe to run multiple times
sudo -u www-data "${CAKE}" Admin runUpdates || true
sudo -u www-data "${CAKE}" Admin cleanCaches || true

echo "=== [6/7] Resetting admin password ==="
# This will succeed if the user exists; otherwise userInit then set password
if ! sudo -u www-data "${CAKE}" Password "${ADMIN_EMAIL}" "${ADMIN_PASS}"; then
  echo "Admin user not found; initializing and retrying password set..."
  sudo -u www-data "${CAKE}" userInit -q || true
  sudo -u www-data "${CAKE}" Password "${ADMIN_EMAIL}" "${ADMIN_PASS}"
fi

echo "=== [7/7] Restarting/Enabling services ==="
systemctl enable --now apache2 redis-server || true
systemctl restart apache2 || true

# Try to detect whether SSL vhost is active on 443
HAS_SSL_VHOST="no"
if apache2ctl -S 2>/dev/null | grep -qiE 'port 443|ssl'; then
  HAS_SSL_VHOST="yes"
fi

echo
echo "=============================================================="
echo "MISP installation complete."
echo "Try opening:"
if [ "${HAS_SSL_VHOST}" = "yes" ]; then
  echo "   https://${MISP_IP}"
else
  echo "   http://${MISP_IP}"
  echo "   (If you prefer HTTPS, enable the SSL vhost and add a cert.)"
fi
echo
echo "Username: ${ADMIN_EMAIL}"
echo "Password: ${ADMIN_PASS}"
echo
echo "Install log: /var/log/misp_install.log"
echo "Web root  : ${MISP_DIR}"
echo "Cake CLI   : ${CAKE}"
echo "=============================================================="
