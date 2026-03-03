from __future__ import annotations

import base64
import os
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives import serialization


def _user_data_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    return Path(base) / "LegacyDoctor"


def key_dir() -> Path:
    d = _user_data_dir() / "keys"
    d.mkdir(parents=True, exist_ok=True)
    return d


def default_signing_key_path() -> Path:
    return key_dir() / "ed25519_signing_key.pem"


def load_or_create_signing_key() -> Ed25519PrivateKey:
    p = default_signing_key_path()
    if p.exists():
        raw = p.read_bytes()
        return serialization.load_pem_private_key(raw, password=None)  # type: ignore[return-value]
    sk = Ed25519PrivateKey.generate()
    pem = sk.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    p.write_bytes(pem)
    return sk


def public_key_b64(sk: Ed25519PrivateKey) -> str:
    pk = sk.public_key()
    raw = pk.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return base64.b64encode(raw).decode("ascii")


def sign_bytes(sk: Ed25519PrivateKey, payload: bytes) -> bytes:
    return sk.sign(payload)


def verify_bytes(public_key_b64_str: str, payload: bytes, signature_b64_str: str) -> bool:
    try:
        pk_raw = base64.b64decode(public_key_b64_str)
        sig_raw = base64.b64decode(signature_b64_str)
        pk = Ed25519PublicKey.from_public_bytes(pk_raw)
        pk.verify(sig_raw, payload)
        return True
    except Exception:
        return False
