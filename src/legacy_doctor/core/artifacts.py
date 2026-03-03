from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


def utc_now_rfc3339() -> str:
    import datetime as _dt
    return _dt.datetime.now(tz=_dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def norm_rel_path(p: str) -> str:
    t = p.replace("\\", "/")
    while t.startswith("/"):
        t = t[1:]
    return t


def canonical_json_bytes(obj: Any) -> bytes:
    s = json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n"
    return s.encode("utf-8")


def sha256_hex_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file_hex(path: str | Path, chunk_size: int = 8 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk_size)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def write_text_utf8_lf(path: str | Path, text: str) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8"))


def write_bytes(path: str | Path, data: bytes) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def write_sha256_sidecar_for_bytes(target_path: str | Path, data: bytes) -> str:
    digest = sha256_hex_bytes(data)
    sidecar = str(target_path) + ".sha256"
    write_text_utf8_lf(sidecar, digest + "\n")
    return sidecar


def write_sha256_sidecar_for_file(target_path: str | Path) -> str:
    digest = sha256_file_hex(target_path)
    sidecar = str(target_path) + ".sha256"
    write_text_utf8_lf(sidecar, digest + "\n")
    return sidecar


def write_sha256sums_txt(job_root: str | Path, rows: Iterable[tuple[str, str]]) -> str:
    job_root = Path(job_root)
    lines = []
    norm_rows = [(h, norm_rel_path(p)) for (h, p) in rows]
    norm_rows.sort(key=lambda x: x[1])
    for h, p in norm_rows:
        lines.append(f"{h}  {p}")
    text = "\n".join(lines) + ("\n" if lines else "")
    out_path = job_root / "sha256sums.txt"
    write_text_utf8_lf(out_path, text)
    return str(out_path)


@dataclass(frozen=True)
class ManifestPaths:
    job_root: str
    manifest_json: str
    manifest_json_sha256: str
    sha256sums_txt: str
    manifest_sig: str
    bundle_tar: str
    bundle_tar_enc: str
    bundle_tar_enc_sha256: str

    @staticmethod
    def for_job(job_root: str | Path) -> "ManifestPaths":
        jr = str(Path(job_root))
        return ManifestPaths(
            job_root=jr,
            manifest_json=str(Path(jr) / "manifest.json"),
            manifest_json_sha256=str(Path(jr) / "manifest.json.sha256"),
            sha256sums_txt=str(Path(jr) / "sha256sums.txt"),
            manifest_sig=str(Path(jr) / "manifest.sig"),
            bundle_tar=str(Path(jr) / "bundle.tar"),
            bundle_tar_enc=str(Path(jr) / "bundle.tar.enc"),
            bundle_tar_enc_sha256=str(Path(jr) / "bundle.tar.enc.sha256"),
        )


def write_manifest_json(job_root: str | Path, manifest_obj: dict[str, Any]) -> ManifestPaths:
    mp = ManifestPaths.for_job(job_root)
    b = canonical_json_bytes(manifest_obj)
    write_bytes(mp.manifest_json, b)
    write_text_utf8_lf(mp.manifest_json_sha256, sha256_hex_bytes(b) + "\n")
    return mp
