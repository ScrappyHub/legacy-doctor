from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from legacy_doctor.core.artifacts import sha256_file_hex
from legacy_doctor.core.keys import verify_bytes


def _read_text(path: str | Path) -> str:
    return Path(path).read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")


def _parse_sha256_sidecar(path: str | Path) -> str:
    t = _read_text(path).strip()
    if not t or len(t) < 64:
        raise ValueError(f"Invalid sha256 sidecar: {path}")
    return t.splitlines()[0].strip()


def _load_manifest(manifest_path: str | Path) -> dict[str, Any]:
    raw = Path(manifest_path).read_bytes()
    obj = json.loads(raw.decode("utf-8"))
    if not isinstance(obj, dict):
        raise ValueError("manifest.json is not an object")
    return obj


def _hash_bytes_hex(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def verify_job(job_root: str | Path) -> dict[str, Any]:
    jr = Path(job_root)
    manifest_path = jr / "manifest.json"
    manifest_sha_path = jr / "manifest.json.sha256"
    sums_path = jr / "sha256sums.txt"
    sig_path = jr / "manifest.sig"

    result: dict[str, Any] = {
        "job_root": str(jr),
        "status": "verified_failed",
        "checks": {
            "manifest_hash": False,
            "signature": False,
            "file_hashes": False,
            "bundle_hash": None,
        },
        "mismatches": [],
        "missing": [],
        "notes": [],
    }

    if not manifest_path.exists():
        result["missing"].append("manifest.json")
        return result
    if not manifest_sha_path.exists():
        result["missing"].append("manifest.json.sha256")
        return result
    if not sums_path.exists():
        result["missing"].append("sha256sums.txt")
        return result

    manifest_raw = manifest_path.read_bytes()
    manifest_hex = _hash_bytes_hex(manifest_raw)
    expected_manifest_hex = _parse_sha256_sidecar(manifest_sha_path)

    if manifest_hex != expected_manifest_hex:
        result["mismatches"].append({"kind": "manifest_hash", "expected": expected_manifest_hex, "actual": manifest_hex})
    else:
        result["checks"]["manifest_hash"] = True

    manifest_obj = _load_manifest(manifest_path)
    files = manifest_obj.get("files") or []
    if not isinstance(files, list):
        files = []

    # signature check (optional but canonical if present)
    if sig_path.exists():
        try:
            sig_obj = json.loads(sig_path.read_text(encoding="utf-8"))
            pub = sig_obj.get("public_key")
            sig_b64 = sig_obj.get("signature")
            if isinstance(pub, str) and isinstance(sig_b64, str):
                payload = bytes.fromhex(expected_manifest_hex)  # sign the manifest hash bytes
                ok = verify_bytes(pub, payload, sig_b64)
                result["checks"]["signature"] = bool(ok)
                if not ok:
                    result["mismatches"].append({"kind": "signature", "message": "Signature verification failed"})
            else:
                result["mismatches"].append({"kind": "signature", "message": "Invalid manifest.sig format"})
        except Exception as e:
            result["mismatches"].append({"kind": "signature", "message": f"Error reading manifest.sig: {e}"})
    else:
        result["checks"]["signature"] = False
        result["notes"].append("manifest.sig not present")

    # file hashes check via sha256sums.txt
    sums_lines = _read_text(sums_path).splitlines()
    sums: dict[str, str] = {}
    for ln in sums_lines:
        ln = ln.strip()
        if not ln:
            continue
        parts = ln.split("  ", 1)
        if len(parts) != 2:
            continue
        h, p = parts[0].strip(), parts[1].strip().replace("\\", "/")
        if h and p:
            sums[p] = h

    # determine root for file existence: manifest["source"]["source_root"] or sibling exports folder
    source_root = None
    src = manifest_obj.get("source") or {}
    if isinstance(src, dict):
        sr = src.get("source_root")
        if isinstance(sr, str) and sr:
            source_root = sr

    exports_dir = jr / "exports"
    base_dir = Path(source_root) if source_root and Path(source_root).exists() else exports_dir

    missing_files = 0
    mismatched_files = 0
    checked_files = 0

    for f in files:
        if not isinstance(f, dict):
            continue
        rel = f.get("path")
        expect = f.get("sha256")
        if not isinstance(rel, str) or not rel:
            continue
        rel = rel.replace("\\", "/").lstrip("/")
        checked_files += 1

        abs_path = base_dir / rel.replace("/", "\\")
        if not abs_path.exists() or not abs_path.is_file():
            missing_files += 1
            result["missing"].append(rel)
            continue

        actual = sha256_file_hex(abs_path)
        expect_sums = sums.get(rel)

        if isinstance(expect, str) and expect and actual != expect:
            mismatched_files += 1
            result["mismatches"].append({"kind": "file_hash", "path": rel, "expected": expect, "actual": actual})
        if expect_sums and actual != expect_sums:
            mismatched_files += 1
            result["mismatches"].append({"kind": "sha256sums", "path": rel, "expected": expect_sums, "actual": actual})

    if missing_files == 0 and mismatched_files == 0:
        result["checks"]["file_hashes"] = True
    else:
        result["checks"]["file_hashes"] = False

    # optional bundle hash
    enc = jr / "bundle.tar.enc"
    enc_sha = jr / "bundle.tar.enc.sha256"
    if enc.exists() and enc_sha.exists():
        try:
            exp = _parse_sha256_sidecar(enc_sha)
            act = sha256_file_hex(enc)
            result["checks"]["bundle_hash"] = (exp == act)
            if exp != act:
                result["mismatches"].append({"kind": "bundle_hash", "expected": exp, "actual": act})
        except Exception as e:
            result["checks"]["bundle_hash"] = False
            result["mismatches"].append({"kind": "bundle_hash", "message": str(e)})

    # final status
    if result["checks"]["manifest_hash"] and result["checks"]["file_hashes"] and (result["checks"]["signature"] in (True, False)):
        if result["checks"]["signature"] is True:
            result["status"] = "verified_ok"
        else:
            result["status"] = "verified_partial"
    else:
        if result["checks"]["manifest_hash"] and not result["checks"]["file_hashes"] and missing_files > 0 and mismatched_files == 0:
            result["status"] = "verified_partial"
        else:
            result["status"] = "verified_failed"

    result["stats"] = {
        "files_checked": checked_files,
        "files_missing": missing_files,
        "files_mismatched": mismatched_files,
    }
    return result
