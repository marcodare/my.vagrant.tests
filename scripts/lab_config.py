"""Validazione statica delle configurazioni dei laboratori."""

from __future__ import annotations

import ipaddress
import json
import re
from pathlib import Path
from typing import Any

# VirtualBox su Linux consente le reti host-only elencate in
# /etc/vbox/networks.conf. Senza quel file vale il solo 192.168.56.0/21, che si
# ferma a 192.168.63.255 e taglierebbe fuori i lab Kubernetes. Il progetto
# dichiara qui il pool che configure.host.sh garantisce sull'host. Servono due
# reti perché 56-71 non è esprimibile con un singolo prefisso: il confine /20
# cade su 192.168.48.0 e 192.168.64.0.
HOSTONLY_POOL = (
    ipaddress.IPv4Network("192.168.56.0/21"),
    ipaddress.IPv4Network("192.168.64.0/21"),
)
SUBNET_MIN = min(int(net.network_address.packed[2]) for net in HOSTONLY_POOL)
SUBNET_MAX = max(int(net.broadcast_address.packed[2]) for net in HOSTONLY_POOL)

ROLE_BOXES = {
    "pve": "bento/debian-13",
    "pbs": "bento/debian-13",
    "manager": "bento/ubuntu-22.04",
    "ha-manager": "bento/ubuntu-22.04",
    "kvm": "bento/ubuntu-22.04",
    "os-controller": "bento/ubuntu-24.04",
    "os-compute": "bento/ubuntu-24.04",
    "zsvirt": "local/zsvirt-h84r",
    "k3s-control": "bento/ubuntu-24.04",
    "k3s-worker": "bento/ubuntu-24.04",
    "k8s-lb": "bento/ubuntu-24.04",
    "k8s-control": "bento/ubuntu-24.04",
    "k8s-worker": "bento/ubuntu-24.04",
    "debian": "bento/debian-13",
    # OPNsense non ha una box ufficiale: si parte da FreeBSD pulito e lo si
    # converte con opnsense-bootstrap, il metodo documentato dal progetto.
    "opnsense": "bento/freebsd-14.3",
}
# Il ruolo "linux" è l'unico in cui ogni nodo dichiara la propria box: serve al
# lab multi-distribuzione, dove Ubuntu e Rocky convivono nella stessa cartella.
# Le versioni sono fissate per box perché non esiste una release Bento comune
# a tutte: Ubuntu 26.04 è pubblicata solo dalla 202606.01.0 in poi.
LINUX_BOXES = {
    "bento/ubuntu-24.04": "202510.26.0",
    "bento/ubuntu-26.04": "202606.01.0",
    "bento/rockylinux-9": "202510.26.0",
    "bento/rockylinux-10": "202510.26.0",
}
PRODUCT_VERSIONS = {
    "pve": "9.2",
    "pbs": "4.2",
    "manager": "4.23",
    "ha-manager": "4.23",
    "kvm": "4.23",
    "k3s-control": "v1.36.4+k3s1",
    "k3s-worker": "v1.36.4+k3s1",
    "k8s-control": "1.37",
    "k8s-worker": "1.37",
    "opnsense": "26.1",
}


def integer(value: object, minimum: int, maximum: int, label: str) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(f"{label}: richiesto intero tra {minimum} e {maximum}")
    return value


def load_spec(directory: Path) -> dict[str, Any]:
    """Legge solo lab.json; rifiuta topologie non coerenti prima di Vagrant."""
    spec = json.loads((directory / "lab.json").read_text(encoding="utf-8"))
    if not isinstance(spec, dict):
        raise ValueError("lab.json deve contenere un oggetto")
    if spec.get("id") != directory.name or not re.fullmatch(
        r"[A-Za-z0-9_]+", spec["id"]
    ):
        raise ValueError("ID non valido o diverso dalla cartella")
    integer(spec.get("subnet"), SUBNET_MIN, SUBNET_MAX, "subnet")
    integer(spec.get("mac_id", spec["subnet"]), 1, 255, "mac_id")
    if spec.get("netmask", "255.255.255.0") not in {"255.255.255.0", "255.255.255.128"}:
        raise ValueError("Netmask prevista /24 o /25")
    if spec.get("box") not in set(ROLE_BOXES.values()) | set(LINUX_BOXES):
        raise ValueError("Box non prevista")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", spec.get("box_version", "")):
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
        # Un nodo può dichiarare la propria box: serve ai lab multi-distribuzione
        # e a quelli con un'appliance accanto ai nodi Linux. Senza override vale
        # la box del lab.
        box = node.get("box", spec["box"])
        box_version = node.get("box_version", spec["box_version"])
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", str(box_version)):
            raise ValueError("Versione box del nodo non valida")
        if node.get("role") == "linux":
            if box not in LINUX_BOXES:
                raise ValueError("Nodo linux senza box prevista")
            if box_version != LINUX_BOXES[box]:
                raise ValueError("Versione box diversa da quella fissata")
        elif node.get("role") not in ROLE_BOXES:
            raise ValueError("Ruolo non valido")
        elif box != ROLE_BOXES[node["role"]]:
            raise ValueError("Box incompatibile con il ruolo")
        if node["role"] in PRODUCT_VERSIONS:
            versions = spec.get("versions", {})
            if (
                not isinstance(versions, dict)
                or versions.get(node["role"]) != PRODUCT_VERSIONS[node["role"]]
            ):
                raise ValueError(
                    "Versione software diversa dal ramo previsto dal progetto"
                )
        if "attach_internal" in node and type(node["attach_internal"]) is not bool:
            raise ValueError("attach_internal deve essere booleano")
        if "networks" in node and (
            not isinstance(node["networks"], list)
            or len(set(node["networks"])) != len(node["networks"])
        ):
            raise ValueError("networks deve essere una lista senza duplicati")
        if "api_host_port" in node:
            integer(node["api_host_port"], 1024, 65535, "api_host_port")
    sans = spec.get("api_sans", [])
    if not isinstance(sans, list) or not all(
        isinstance(san, str) and san for san in sans
    ):
        raise ValueError("api_sans deve essere una lista di stringhe non vuote")
    vip = spec.get("api_vip_host")
    if vip is not None:
        integer(vip, 2, 254, "api_vip_host")
        if vip in hosts:
            raise ValueError("api_vip_host coincide con l'IP di un nodo")
    netmask = spec.get("netmask", "255.255.255.0")
    segments = {
        ipaddress.IPv4Interface(
            f"192.168.{spec['subnet']}.{node['host']}/{netmask}"
        ).network
        for node in nodes
    }
    if len(segments) != 1:
        raise ValueError(
            "Tutti i nodi devono appartenere allo stesso segmento host-only"
        )
    segment = next(iter(segments))
    if not any(segment.subnet_of(allowed) for allowed in HOSTONLY_POOL):
        pool = ", ".join(str(allowed) for allowed in HOSTONLY_POOL)
        raise ValueError(
            f"Segmento host-only {segment} fuori dal pool consentito ({pool}): "
            "VirtualBox rifiuterebbe la rete e vagrant up fallirebbe"
        )
    for node in nodes:
        address = ipaddress.IPv4Address(f"192.168.{spec['subnet']}.{node['host']}")
        if address in {
            segment.network_address,
            segment.broadcast_address,
            segment.network_address + 1,
        }:
            raise ValueError("IP riservato a rete, broadcast o adattatore host-only")
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
        internal_segment = ipaddress.IPv4Network(f"{prefix}.0/24")
        if (
            not internal_segment.subnet_of(ipaddress.IPv4Network("10.0.0.0/8"))
            or prefix in prefixes
        ):
            raise ValueError("Rete interna duplicata o fuori 10.0.0.0/8")
        prefixes.add(prefix)
    for node in nodes:
        if not set(node.get("networks", [])) <= network_names:
            raise ValueError("networks cita una rete interna non dichiarata")
    return spec


def node_networks(spec: dict[str, Any], node: dict[str, Any]) -> list[dict[str, Any]]:
    """Reti interne collegate a un nodo, nell'ordine delle NIC da 3 in poi.

    `attach_internal=false` esclude tutte le reti; `networks` ne sceglie un
    sottoinsieme, come nei lab in cui ogni nodo sta su un segmento diverso.
    """
    if not node.get("attach_internal", True):
        return []
    networks: list[dict[str, Any]] = spec.get("internal_networks", [])
    if "networks" not in node:
        return networks
    return [network for network in networks if network["name"] in node["networks"]]


def mac_address(subnet: int, node: int, slot: int, *, colon: bool = False) -> str:
    raw = f"080027{subnet:02x}{node:02x}{slot:02x}"
    return ":".join(raw[n : n + 2] for n in range(0, 12, 2)) if colon else raw
