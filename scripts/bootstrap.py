"""Install pinned official development binaries into the ignored .tools directory."""
import io
import json
import platform
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / ".tools"
RELEASES = {"rojo": ("rojo-rbx/rojo", "v7.7.1"), "lune": ("lune-org/lune", "v0.11.1"), "luau": ("luau-lang/luau", "0.745")}
SYSTEM = {"Linux": "linux", "Darwin": "macos", "Windows": "windows"}[platform.system()]
ARCH = "aarch64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"


def download(url):
    req = urllib.request.Request(url, headers={"User-Agent": "EspressoCafeTycoon-build"})
    with urllib.request.urlopen(req, timeout=45) as response:
        return response.read()


DEST.mkdir(exist_ok=True)
for tool, (repo, version) in RELEASES.items():
    suffix = ".exe" if SYSTEM == "windows" else ""
    if (DEST / (tool + suffix)).exists():
        print(f"{tool}: already installed in .tools")
        continue
    release = json.loads(download(f"https://api.github.com/repos/{repo}/releases/tags/{version}"))
    if tool == "luau":
        expected = {"linux": "luau-ubuntu.zip", "macos": "luau-macos.zip", "windows": "luau-windows.zip"}[SYSTEM]
        candidates = [a for a in release["assets"] if a["name"] == expected]
        if SYSTEM == "linux" and ARCH == "aarch64":
            print("Skipping optional Luau compiler: no pinned Linux ARM binary.")
            continue
    else:
        candidates = [a for a in release["assets"] if SYSTEM in a["name"] and ARCH in a["name"] and a["name"].endswith(".zip")]
    if len(candidates) != 1:
        raise SystemExit(f"No unique official {tool} {version} binary for {SYSTEM}/{ARCH}. See {release['html_url']}")
    archive = zipfile.ZipFile(io.BytesIO(download(candidates[0]["browser_download_url"])))
    names = {tool + suffix} if tool != "luau" else {"luau" + suffix, "luau-compile" + suffix, "luau-analyze" + suffix}
    for entry in archive.infolist():
        basename = Path(entry.filename).name
        if basename in names:
            target = DEST / basename
            target.write_bytes(archive.read(entry))
            target.chmod(0o755)
    if not (DEST / (tool + suffix)).exists():
        raise SystemExit(f"Executable missing from official {tool} archive")
    print(f"{tool}: installed {version}")
