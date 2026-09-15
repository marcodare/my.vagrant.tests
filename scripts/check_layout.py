"""Controlli statici delle topologie, senza avviare VM."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from scripts.lab_config import load_spec, mac_address  # noqa: E402


def main() -> None:
    subnets: set[int] = set()
    macs: set[str] = set()
    paths = sorted(ROOT.glob("*/lab.json"))
    if len(paths) != 5:
        raise ValueError("Attesi cinque laboratori")
    for path in paths:
        spec = load_spec(path.parent)
        if spec["subnet"] in subnets:
            raise ValueError(f"Subnet duplicata: {path}")
        subnets.add(spec["subnet"])
        if not (path.parent / "README.md").is_file():
            raise ValueError(f"README mancante: {path}")
        for index, node in enumerate(spec["nodes"], start=1):
            for script in ("base", node["role"]):
                if not (path.parent / f"scripts/provision/{script}.sh").is_file():
                    raise ValueError(f"Provisioner mancante: {path}: {script}")
            for slot in range(2, 3 + len(spec["internal_networks"])):
                mac = mac_address(spec["subnet"], index, slot)
                if mac in macs:
                    raise ValueError(f"MAC duplicato: {mac}")
                macs.add(mac)
        ram = sum(node["memory"] for node in spec["nodes"]) // 1024
        print(f"{spec['id']}: {len(spec['nodes'])} nodi, {ram} GiB RAM")


if __name__ == "__main__":
    main()
