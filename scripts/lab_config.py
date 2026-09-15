"""Validazione statica delle configurazioni dei laboratori."""

from __future__ import annotations

import ipaddress
import json
import re
from pathlib import Path
from typing import Any

ROLES = frozenset({"pve", "pbs", "manager", "kvm"})


def integer(value: object, minimum: int, maximum: int, label: str) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(f"{label}: richiesto intero tra {minimum} e {maximum}")
    return value


def load_spec(directory: Path) -> dict[str, Any]:
    """Legge solo lab.json; rifiuta topologie non coerenti prima di Vagrant."""
    spec = json.loads((directory / "lab.json").read_text(encoding="utf-8"))
    if not isinstance(spec, dict):
        raise ValueError("lab.json deve contenere un oggetto")
    if spec.get("id") != directory.name or not re.fullmatch(r"[a-z0-9_]+", spec["id"]):
        raise ValueError("ID non valido o diverso dalla cartella")
    integer(spec.get("subnet"), 56, 60, "subnet")
    if spec.get("box") not in {"bento/debian-13", "bento/ubuntu-22.04"}:
        raise ValueError("Box non prevista")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", spec.get("box_version", "")):
        raise ValueError("Versione box non valida")
    nodes = spec.get("nodes")
    if not isinstance(nodes, list) or not 1 <= len(nodes) <= 8:
        raise ValueError("Richiesti da 1 a 8 nodi")
    names: set[str] = set()
    hosts: set[int] = set()
    for node in nodes:
        if not isinstance(node, dict):
            raise ValueError("Nodo non valido")
        name = node.get("name", "")
        if not re.fullmatch(r"[a-z][a-z0-9-]+", name) or name in names:
            raise ValueError("Nome nodo non valido o duplicato")
        names.add(name)
        host = integer(node.get("host"), 2, 254, "host")
        if host in hosts:
            raise ValueError("IP duplicato")
        hosts.add(host)
        integer(node.get("memory"), 4096, 65536, "memory")
        integer(node.get("cpus"), 1, 16, "cpus")
        if "disk_gb" in node:
            integer(node["disk_gb"], 10, 1000, "disk_gb")
        if node.get("role") not in ROLES:
            raise ValueError("Ruolo non valido")
        expected = (
            "bento/debian-13"
            if node["role"] in {"pve", "pbs"}
            else "bento/ubuntu-22.04"
        )
        if spec["box"] != expected:
            raise ValueError("Box incompatibile con il ruolo")
    if sum(node["memory"] for node in nodes) > 96 * 1024:
        raise ValueError("Superato budget 96 GiB per lab")
    networks = spec.get("internal_networks", [])
    if not isinstance(networks, list) or len(networks) > 3:
        raise ValueError("Massimo tre reti interne")
    network_names: set[str] = set()
    prefixes: set[str] = set()
    for network in networks:
        if not isinstance(network, dict):
            raise ValueError("Rete non valida")
        name = network.get("name", "")
        if not re.fullmatch(r"[a-z]+", name) or name in network_names:
            raise ValueError("Nome rete non valido o duplicato")
        network_names.add(name)
        prefix = network.get("prefix", "")
        address = ipaddress.IPv4Network(f"{prefix}.0/24")
        if (
            not address.subnet_of(ipaddress.IPv4Network("10.0.0.0/8"))
            or prefix in prefixes
        ):
            raise ValueError("Rete interna duplicata o fuori 10.0.0.0/8")
        prefixes.add(prefix)
    return spec


def mac_address(subnet: int, node: int, slot: int, *, colon: bool = False) -> str:
    raw = f"080027{subnet:02x}{node:02x}{slot:02x}"
    return ":".join(raw[n : n + 2] for n in range(0, 12, 2)) if colon else raw
