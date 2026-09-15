"""Rifiuto delle configurazioni che produrrebbero collisioni o nodi errati."""

import ipaddress
import json
import os
from pathlib import Path

import pytest

from scripts.lab_config import HOSTONLY_POOL, load_spec

ROOT = Path(__file__).resolve().parent.parent


@pytest.mark.parametrize(
    "invalid",
    [
        "duplicate_ip",
        "duplicate_name",
        "wrong_os",
        "oversized_ram",
        "public_network",
        "wrong_version",
    ],
)
def test_rejects_invalid_topologies(tmp_path: Path, invalid: str) -> None:
    directory = tmp_path / "proxmox_3nodes_simple"
    directory.mkdir()
    spec = json.loads((ROOT / directory.name / "lab.json").read_text())
    if invalid == "duplicate_ip":
        spec["nodes"][1]["host"] = spec["nodes"][0]["host"]
    elif invalid == "duplicate_name":
        spec["nodes"][1]["name"] = spec["nodes"][0]["name"]
    elif invalid == "wrong_os":
        spec["box"] = "bento/ubuntu-22.04"
    elif invalid == "oversized_ram":
        for node in spec["nodes"]:
            node["memory"] = 65536
    elif invalid == "public_network":
        spec["internal_networks"] = [{"name": "public", "prefix": "8.8.8"}]
    else:
        spec["versions"]["pve"] = "9.1"
    (directory / "lab.json").write_text(json.dumps(spec))
    with pytest.raises(ValueError):
        load_spec(directory)


def test_all_labs_have_valid_topologies() -> None:
    paths = sorted(ROOT.glob("*/lab.json"))
    assert len(paths) == 11
    for path in paths:
        load_spec(path.parent)


def test_manual_start_files_do_not_run_provisioners() -> None:
    paths = sorted(ROOT.glob("*/Vagrant.start"))
    assert len(paths) == 11
    for path in paths:
        source = path.read_text()
        assert ".provision" not in source
        assert "auto_config: false" in source


def test_pbs_is_not_attached_to_ceph_network() -> None:
    spec = load_spec(ROOT / "proxmox_3nodes_ceph_backup")
    assert len(spec["internal_networks"]) == 1
    pbs = next(node for node in spec["nodes"] if node["role"] == "pbs")
    assert pbs["attach_internal"] is False


@pytest.mark.parametrize(
    "directory",
    [
        "cloudstack_1manager_3nodes",
        "cloudstack_HAmanager_3nodes_linbit",
        "cloudstack_HAmanager_3nodes_ceph",
    ],
)
def test_cloudstack_has_private_network_and_public_bridge(directory: str) -> None:
    spec = load_spec(ROOT / directory)
    assert spec["internal_networks"] == [
        {"name": "private", "prefix": f"10.{spec['subnet']}.0"}
    ]
    provisioner = (ROOT / directory / "scripts/provision/kvm.sh").read_text()
    assert "public.network.device=cloudbr1" in provisioner
    assert "private.network.device=cloudbr0" in provisioner


def test_rejects_nodes_in_different_halves_of_hostonly_network(tmp_path: Path) -> None:
    directory = tmp_path / "openstack_3nodes_simple"
    directory.mkdir()
    spec = json.loads((ROOT / directory.name / "lab.json").read_text())
    spec["nodes"][1]["host"] = 150
    (directory / "lab.json").write_text(json.dumps(spec))
    with pytest.raises(ValueError, match="stesso segmento"):
        load_spec(directory)


def test_rejects_hostonly_segment_outside_virtualbox_pool(tmp_path: Path) -> None:
    """Una subnet fuori dal pool fa fallire vagrant up: va fermata prima."""
    directory = tmp_path / "k3s_1control_3workers"
    directory.mkdir()
    spec = json.loads((ROOT / directory.name / "lab.json").read_text())
    spec["subnet"] = 72  # subito oltre 192.168.64.0/21
    (directory / "lab.json").write_text(json.dumps(spec))
    with pytest.raises(ValueError):
        load_spec(directory)


def test_all_labs_use_allowed_hostonly_ranges() -> None:
    for path in sorted(ROOT.glob("*/lab.json")):
        spec = load_spec(path.parent)
        netmask = spec.get("netmask", "255.255.255.0")
        segment = ipaddress.IPv4Interface(
            f"192.168.{spec['subnet']}.{spec['nodes'][0]['host']}/{netmask}"
        ).network
        assert any(segment.subnet_of(allowed) for allowed in HOSTONLY_POOL)


def test_vagrantfiles_do_not_hardcode_lab_addresses() -> None:
    """Indirizzi ripetuti a mano fanno divergere i due percorsi da lab.json."""
    for path in sorted(ROOT.glob("*/lab.json")):
        spec = load_spec(path.parent)
        for name in ("Vagrantfile", "Vagrant.start"):
            source = (path.parent / name).read_text()
            code = "\n".join(
                line
                for line in source.splitlines()
                if not line.lstrip().startswith("#")
            )
            where = f"{path.parent.name}/{name}"
            for network in spec.get("internal_networks", []):
                assert network["prefix"] not in code, where
            assert f"192.168.{spec['subnet']}." not in code, where


def test_api_host_ports_are_unique_across_labs() -> None:
    seen: dict[int, str] = {}
    for path in sorted(ROOT.glob("*/lab.json")):
        spec = load_spec(path.parent)
        for node in spec["nodes"]:
            port = node.get("api_host_port")
            if port is None:
                continue
            assert port not in seen
            seen[port] = f"{spec['id']}/{node['name']}"
    assert len(seen) == 3  # control1 di k3s, lb1 e lb2 di k8s


@pytest.mark.parametrize(
    "directory", ["k3s_1control_3workers", "k8s_hacontrol_3workers"]
)
def test_kubernetes_labs_publish_the_api_to_host_and_lan(directory: str) -> None:
    """L'API deve restare raggiungibile da Bosgame e Mac dopo ogni modifica."""
    spec = load_spec(ROOT / directory)
    published = [n for n in spec["nodes"] if "api_host_port" in n]
    assert published, directory
    source = (ROOT / directory / "Vagrantfile").read_text()
    assert "forwarded_port" in source
    assert "host_ip: '0.0.0.0'" in source
    helper = ROOT / directory / "scripts/kubeconfig.sh"
    assert helper.is_file() and os.access(helper, os.X_OK)
    assert spec["api_sans"], "senza SAN il certificato non copre l'accesso remoto"


def test_provisioners_receive_hosts_instead_of_a_fixed_list() -> None:
    """Il blocco /etc/hosts deve venire da lab.json, non da un elenco fisso."""
    for directory in sorted(ROOT.glob("*/scripts/provision/base.sh")):
        source = directory.read_text()
        assert "hosts=$" in source, directory
        assert 'tr \';\' \'\\n\' <<< "$hosts"' in source, directory
