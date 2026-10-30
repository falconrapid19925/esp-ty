"""Compile all Luau, execute economy scenarios, build and inspect the Roblox place."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def tool(name):
    local = ROOT / ".tools" / (name + (".exe" if os.name == "nt" else ""))
    return str(local) if local.exists() else shutil.which(name)


def run(args):
    subprocess.run(args, cwd=ROOT, check=True)


compiler = tool("luau-compile")
if compiler:
    sources = sorted(ROOT.glob("src/**/*.luau")) + sorted(ROOT.glob("tests/**/*.luau"))
    run([compiler, "--null", *map(str, sources)])
    print(f"PASS: Luau syntax compilation ({len(sources)} files)", flush=True)
else:
    print("Luau compiler not installed; syntax compilation skipped.", flush=True)

if not tool("lune") or not tool("rojo"):
    raise SystemExit("Install pinned tools from aftman.toml first (aftman install).")
for test in sorted(ROOT.glob("tests/*.spec.luau")):
    run([tool("lune"), "run", str(test.relative_to(ROOT))])
asset_root = ROOT / "assets" / "source"
manifest = json.loads((asset_root / "manifest.json").read_text())
for asset in manifest["files"]:
    data = (asset_root / asset["file"]).read_bytes()
    assert len(data) == asset["bytes"], f"Asset size mismatch: {asset['file']}"
    assert hashlib.sha256(data).hexdigest() == asset["sha256"], f"Asset checksum mismatch: {asset['file']}"
print(f"PASS: {len(manifest['files'])} sourced CC0 files match the download manifest", flush=True)
output = ROOT / "build" / "EspressoCafeTycoon.rbxlx"
output.parent.mkdir(exist_ok=True)
run([tool("rojo"), "build", "default.project.json", "-o", str(output)])
place = ET.parse(output).getroot()
asset_services = [n for n in place.iter("Item") if n.get("class") == "AssetService"]
assert asset_services, "Free asset-loading service configuration missing"
assert any(n.get("name") == "AllowInsertFreeAssets" and n.text == "true"
           for service in asset_services for n in service.iter("bool")), "Free asset loading not configured"
names = {}
for item in place.iter("Item"):
    properties = item.find("Properties")
    if properties is not None:
        name = next((node.text for node in properties if node.get("name") == "Name"), None)
        names[name] = item.get("class")
for name, class_name in {
    "Config": "ModuleScript", "Economy": "ModuleScript", "World": "ModuleScript",
    "GameService": "ModuleScript", "DataService": "ModuleScript",
    "Assets": "ModuleScript", "AssetCatalog": "ModuleScript",
}.items():
    assert names.get(name) == class_name, f"Missing {class_name}: {name}"
scripts = [item for item in place.iter("Item") if item.get("class") == "Script"]
clients = [item for item in place.iter("Item") if item.get("class") == "LocalScript"]
assert scripts and clients, "Both server and client entrypoints must be exported"
source_count = sum(1 for n in place.iter() if n.get("name") == "Source" and n.text)
print(f"PASS: exported {source_count} Luau sources in {output.name} ({output.stat().st_size:,} bytes)")
print("Roblox engine/visual/network playtests still require Studio; see docs/STUDIO_TEST_PLAN.md.")
