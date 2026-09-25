#!/usr/bin/env python3
"""Refresh artifact hashes for the existing exact pins; never update versions.

Download PyPI release metadata for each exact pin, verify published wheel
SHA-256 digests, and generate requirements.lock. Source archives are deliberately
excluded in accordance with Omarchy plugin marketplace security policy.
"""
from pathlib import Path
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

PACKAGES = [
    ("aiofiles", "25.1.0"),
    ("androidtvremote2", "0.3.2"),
    ("cffi", "2.1.1"),
    ("cryptography", "50.0.1"),
    ("protobuf", "7.36.2"),
    ("pycparser", "3.0"),
]


def main():
    lock = ROOT / "requirements.lock"
    lines = [
        "# Exact pins and verified wheel SHA-256 hashes from https://pypi.org.",
        "# Regenerate explicitly: python3 scripts/lock-dependencies.py",
        "# Installation accepts wheels only; source builds are not permitted.",
        "--only-binary=:all:",
        "--require-hashes",
        "",
    ]
    for name, ver in PACKAGES:
        url = f"https://pypi.org/pypi/{name}/{ver}/json"
        req = urllib.request.Request(url, headers={"User-Agent": "pip-locker/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.load(resp)
        wheels = [u for u in data["urls"] if u["packagetype"] == "bdist_wheel" and not u.get("yanked", False)]
        if not wheels:
            raise ValueError(f"No non-yanked wheels found for {name}=={ver}")
        wheels.sort(key=lambda x: x["filename"])
        lines.append(f"{name}=={ver} \\")
        for i, w in enumerate(wheels):
            digest = w["digests"]["sha256"]
            continuation = " \\" if i < len(wheels) - 1 else ""
            lines.append(f"    --hash=sha256:{digest}{continuation}")
        lines.append("")
        print(f"Verified {name}=={ver}: {len(wheels)} wheels")
    lock.write_text("\n".join(lines))
    print(f"Successfully wrote {lock}")


if __name__ == "__main__":
    main()
