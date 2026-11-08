#!/usr/bin/env bash
# Nova Runtime Desktop Integration Script (Linux)
# Part of Nova Programming Language v0.31.02
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOVA_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "==> Registering Nova .nova file association and desktop launcher..."

# 1. User application and MIME directories
APP_DIR="${HOME}/.local/share/applications"
MIME_DIR="${HOME}/.local/share/mime/packages"
ICON_DIR="${HOME}/.local/share/icons/hicolor/512x512/apps"

mkdir -p "${APP_DIR}" "${MIME_DIR}" "${ICON_DIR}"

# 2. Copy desktop file and adjust Exec/Icon paths
sed -e "s|Exec=nova-runner|Exec=${NOVA_ROOT}/bin/nova-runner|g" \
    -e "s|Icon=.*|Icon=${ICON_DIR}/nova.png|g" \
    "${SCRIPT_DIR}/nova-runner.desktop" > "${APP_DIR}/nova-runner.desktop"

# 3. Copy MIME xml
cp -f "${SCRIPT_DIR}/nova.xml" "${MIME_DIR}/nova.xml"

# 4. Copy branding icon
cp -f "${NOVA_ROOT}/assets/branding/icon_512.png" "${ICON_DIR}/nova.png"

# 5. Update databases
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APP_DIR}"
fi

if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "${HOME}/.local/share/mime"
fi

if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default nova-runner.desktop application/x-nova
fi

echo "==> Done! Double-clicking any .nova file in your file manager will now run it via Nova Runtime."
