#!/usr/bin/env bash
# Setup script for omarchy-googletv dependencies
set -euo pipefail

echo "==> Setting up Google TV Remote dependencies for Omarchy Shell..."

DATA_DIR="${HOME}/.config/omarchy/googletv"
VENV_DIR="${DATA_DIR}/.venv"

mkdir -p "${DATA_DIR}"

if [[ ! -d "${VENV_DIR}" ]]; then
    echo "==> Creating Python virtual environment in ${VENV_DIR}..."
    python3 -m venv "${VENV_DIR}"
fi

echo "==> Installing androidtvremote2 and cryptography..."
"${VENV_DIR}/bin/pip" install --upgrade pip -q
"${VENV_DIR}/bin/pip" install -q "androidtvremote2>=0.0.14" "cryptography"

echo "==> Setup complete! Dependencies installed in ${VENV_DIR}"
