"""Controlli statici delle topologie, senza avviare VM."""

from __future__ import annotations

import ipaddress
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from scripts.lab_config import load_spec, mac_address  # noqa: E402


def main() -> None:
    subnets: set[ipaddress.IPv4Network] = set()
    macs: set[str] = set()
    paths = sorted(ROOT.glob("*/lab.json"))
    if not paths:
        raise ValueError("Nessun laboratorio trovato")
    for path in paths:
        spec = load_spec(path.parent)
        first_ip = f"192.168.{spec['subnet']}.{spec['nodes'][0]['host']}"
        netmask = spec.get("netmask", "255.255.255.0")
        segment = ipaddress.IPv4Interface(f"{first_ip}/{netmask}").network
        if any(segment.overlaps(other) for other in subnets):
            raise ValueError(f"Subnet sovrapposta: {path}")
        subnets.add(segment)
        assisted = path.parent / "Vagrantfile"
        readme = path.parent / "README.md"
        steps = path.parent / "STEPS.md"
        manual = path.parent / "Vagrant.start"
        if not assisted.is_file():
            raise ValueError(f"Vagrantfile mancante: {path}")
        if not readme.is_file():
            raise ValueError(f"README mancante: {path}")
        if not steps.is_file():
            raise ValueError(f"STEPS mancante: {path}")
        if not manual.is_file():
            raise ValueError(f"Vagrant.start mancante: {path}")
        readme_text = readme.read_text(encoding="utf-8")
        if (
            "VAGRANT_VAGRANTFILE=Vagrant.start vagrant up" not in readme_text
            or "STEPS.md" not in readme_text
        ):
            raise ValueError(f"README senza percorso basic o STEPS: {path}")
        steps_text = steps.read_text(encoding="utf-8").lower()
        if "bare metal" not in steps_text or "vagrant.start" not in steps_text:
            raise ValueError(f"STEPS non portabile o senza percorso basic: {path}")
        manual_text = manual.read_text(encoding="utf-8")
        if ".provision" in manual_text or "auto_config: false" not in manual_text:
            raise ValueError(f"Vagrant.start configura il guest: {path}")
        for index, node in enumerate(spec["nodes"], start=1):
            required: tuple[str, ...] = (
                () if node["role"] == "zsvirt" else ("base", node["role"])
            )
            if node["role"] == "kvm" and spec.get("storage_backend"):
                required += ("storage",)
            for script in required:
                if not (path.parent / f"scripts/provision/{script}.sh").is_file():
                    raise ValueError(f"Provisioner mancante: {path}: {script}")
            networks = (
                spec["internal_networks"] if node.get("attach_internal", True) else []
            )
            for slot in range(2, 3 + len(networks)):
                mac = mac_address(spec.get("mac_id", spec["subnet"]), index, slot)
                if mac in macs:
                    raise ValueError(f"MAC duplicato: {mac}")
                macs.add(mac)
        ram = sum(node["memory"] for node in spec["nodes"]) // 1024
        print(f"{spec['id']}: {len(spec['nodes'])} nodi, {ram} GiB RAM")


if __name__ == "__main__":
    main()
