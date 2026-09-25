#!/usr/bin/env bash
# Setup script for omarchy-googletv dependencies
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
echo "==> Setting up Google TV Remote dependencies for Omarchy Shell..."

data_dir="${HOME}/.config/omarchy/googletv"
venv_dir="${data_dir}/.venv"

mkdir -p "${data_dir}"

if [[ ! -d "${venv_dir}" ]]; then
    echo "==> Creating Python virtual environment in ${venv_dir}..."
    python3 -m venv "${venv_dir}"
fi

echo "==> Installing pinned dependencies with verified artifact hashes..."
"${venv_dir}/bin/python" -m pip install --require-hashes --only-binary=:all: -r "${script_dir}/requirements.lock"

echo "==> Setup complete! Dependencies installed in ${venv_dir}"
