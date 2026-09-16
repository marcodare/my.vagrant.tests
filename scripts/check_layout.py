"""Controlli statici delle topologie, senza avviare VM."""

from __future__ import annotations

import ipaddress
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from scripts.lab_config import (  # noqa: E402
    HOSTONLY_POOL,
    load_spec,
    mac_address,
    node_networks,
)


def main() -> None:
    subnets: set[ipaddress.IPv4Network] = set()
    macs: set[str] = set()
    # Le porte pubblicate sull'host sono globali: due lab che ne condividono una
    # collidono anche restando spenti a turno, perché Vagrant le assegna all'up.
    api_ports: dict[int, str] = {}
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
        manual_name = (
            "Vagrantfile.start"
            if (path.parent / "Vagrantfile.start").is_file()
            else "Vagrant.start"
        )
        manual = path.parent / manual_name
        if not assisted.is_file():
            raise ValueError(f"Vagrantfile mancante: {path}")
        if not readme.is_file():
            raise ValueError(f"README mancante: {path}")
        if not steps.is_file():
            raise ValueError(f"STEPS mancante: {path}")
        if not manual.is_file():
            raise ValueError(f"Definizione Vagrant basic mancante: {path}")
        vbguest_guard = (
            "config.vbguest.auto_update = false "
            "if Vagrant.has_plugin?('vagrant-vbguest')"
        )
        assisted_text = assisted.read_text(encoding="utf-8")
        manual_text = manual.read_text(encoding="utf-8")
        for definition, source in ((assisted, assisted_text), (manual, manual_text)):
            if vbguest_guard not in source:
                raise ValueError(
                    f"Protezione da vagrant-vbguest mancante: {definition}"
                )
        readme_text = readme.read_text(encoding="utf-8")
        if (
            f"VAGRANT_VAGRANTFILE={manual_name} vagrant up" not in readme_text
            or "STEPS.md" not in readme_text
        ):
            raise ValueError(f"README senza percorso basic o STEPS: {path}")
        steps_text = steps.read_text(encoding="utf-8").lower()
        if "bare metal" not in steps_text or manual_name.lower() not in steps_text:
            raise ValueError(f"STEPS non portabile o senza percorso basic: {path}")
        if ".provision" in manual_text or "auto_config: false" not in manual_text:
            raise ValueError(f"La definizione Vagrant basic configura il guest: {path}")
        for index, node in enumerate(spec["nodes"], start=1):
            # zsvirt è un'appliance senza provisioner; OPNsense ha solo il
            # proprio, perché base.sh dei lab è pensato per guest Linux.
            if node["role"] == "zsvirt":
                required: tuple[str, ...] = ()
            elif node["role"] == "opnsense":
                required = ("opnsense",)
            else:
                required = ("base", node["role"])
            if node["role"] == "kvm" and spec.get("storage_backend"):
                required += ("storage",)
            for script in required:
                if not (path.parent / f"scripts/provision/{script}.sh").is_file():
                    raise ValueError(f"Provisioner mancante: {path}: {script}")
            for slot in range(2, 3 + len(node_networks(spec, node))):
                mac = mac_address(spec.get("mac_id", spec["subnet"]), index, slot)
                if mac in macs:
                    raise ValueError(f"MAC duplicato: {mac}")
                macs.add(mac)
        for node in spec["nodes"]:
            port = node.get("api_host_port")
            if port is None:
                continue
            if port in api_ports:
                raise ValueError(f"Porta host {port} già usata da {api_ports[port]}")
            api_ports[port] = f"{spec['id']}/{node['name']}"
        ram = sum(node["memory"] for node in spec["nodes"]) // 1024
        print(f"{spec['id']}: {len(spec['nodes'])} nodi, {ram} GiB RAM, {segment}")
    pool = ", ".join(str(allowed) for allowed in HOSTONLY_POOL)
    print(f"Segmenti host-only tutti dentro il pool consentito: {pool}.")


if __name__ == "__main__":
    main()
