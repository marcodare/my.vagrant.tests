"""Rifiuto delle configurazioni che produrrebbero collisioni o nodi errati."""

import json
from pathlib import Path

import pytest

from scripts.lab_config import load_spec

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
