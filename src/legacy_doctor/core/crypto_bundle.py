from __future__ import annotations

import os
import tarfile
from pathlib import Path
from typing import Iterable

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


MAGIC = b"LDENC1"
VERSION = b"\x01"
NONCE_LEN = 12


def build_tar(tar_path: str | Path, source_root: str | Path, rel_paths: Iterable[str]) -> str:
    tar_path = Path(tar_path)
    tar_path.parent.mkdir(parents=True, exist_ok=True)
    src = Path(source_root)

    with tarfile.open(tar_path, "w") as tf:
        for rel in rel_paths:
            rel_norm = rel.replace("\\", "/").lstrip("/")
            abs_path = src / rel_norm.replace("/", os.sep)
            if abs_path.is_file():
                tf.add(str(abs_path), arcname=rel_norm, recursive=False)

    return str(tar_path)


def encrypt_aesgcm_bundle(plaintext_path: str | Path, out_enc_path: str | Path, key_32: bytes, job_id: str) -> str:
    pt = Path(plaintext_path).read_bytes()
    aes = AESGCM(key_32)
    nonce = os.urandom(NONCE_LEN)
    aad = (b"legacydoctor|bundle|v1|" + job_id.encode("utf-8"))
    ct = aes.encrypt(nonce, pt, aad)

    out = bytearray()
    out += MAGIC
    out += VERSION
    out += bytes([NONCE_LEN])
    out += nonce
    out += ct

    out_enc_path = Path(out_enc_path)
    out_enc_path.parent.mkdir(parents=True, exist_ok=True)
    out_enc_path.write_bytes(bytes(out))
    return str(out_enc_path)
