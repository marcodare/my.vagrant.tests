"""Rifiuto delle configurazioni che produrrebbero collisioni o nodi errati."""

import json
from pathlib import Path

import pytest

from scripts.lab_config import load_spec

ROOT = Path(__file__).resolve().parent.parent


@pytest.mark.parametrize(
    "invalid",
    ["duplicate_ip", "duplicate_name", "wrong_os", "oversized_ram", "public_network"],
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
    else:
        spec["internal_networks"] = [{"name": "public", "prefix": "8.8.8"}]
    (directory / "lab.json").write_text(json.dumps(spec))
    with pytest.raises(ValueError):
        load_spec(directory)
