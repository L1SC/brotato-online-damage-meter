"""Package only the original OnlineDamageMeter mod, documentation and tests."""
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods-unpacked/CoopFix-OnlineDamageMeter"
VERSION = json.loads((MOD / "manifest.json").read_text(encoding="utf-8"))["version_number"]
DIST = ROOT / "dist"
DOCS = ["docs/online-damage-meter.md", "docs/online-damage-meter-verification.md"]
SUPPORT = [
    "LICENSE", "tools/build_damage_meter.py", "tools/run_damage_meter_tests.py",
    "tests/damage_meter_lan_runtime.gd",
]


def finish(path):
    with ZipFile(path) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(set(archive.namelist()))
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    path.with_suffix(path.suffix + ".sha256").write_text(f"{digest}  {path.name}\n", encoding="utf-8")
    print(path)


def main():
    DIST.mkdir(exist_ok=True)
    mod_files = sorted(path for path in MOD.rglob("*") if path.is_file())
    install = DIST / f"{MOD.name}-{VERSION}.zip"
    with ZipFile(install, "w", compression=ZIP_DEFLATED) as archive:
        for path in mod_files:
            archive.write(path, path.relative_to(ROOT).as_posix())
        archive.write(ROOT / DOCS[0], f"mods-unpacked/{MOD.name}/README.md")
        archive.write(ROOT / DOCS[1], f"mods-unpacked/{MOD.name}/online-damage-meter-verification.md")
    finish(install)

    source = DIST / f"{MOD.name}-{VERSION}-source.zip"
    with ZipFile(source, "w", compression=ZIP_DEFLATED) as archive:
        for path in mod_files + [ROOT / name for name in DOCS + SUPPORT]:
            archive.write(path, path.relative_to(ROOT).as_posix())
    finish(source)


if __name__ == "__main__":
    main()
