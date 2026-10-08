# LD-STORAGE-03P0 — Positive ready-path fixture v1

## Purpose

Prove the positive contract and guard path before implementing a production bounded copy executor.

## What is real

The fixture runs the repository's actual blocked-copy guard and validates its real guard schema. It supplies an isolated, schema-valid contract receipt whose destination is explicit, non-repository, non-overlapping, bounded, preflight-ready, and write-probe-ready.

## What is intentionally synthetic

The host preflight is not replaced or weakened. The synthetic contract exists only inside the disposable fixture root so the positive guard semantics can be tested without declaring any real host volume safe. The fixture performs no copy and writes no destination bytes.

## Proof

Run:

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_positive_ready_path_fixture_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

The green token requires:

```text
preflight_ready:true
execution_allowed_now:true
would_allow_future_bounded_copy:true
would_invoke_future_executor:true
performs_copy:false
writes_destination:false
```

This is 03P0 only. It does not authorize or perform production copying.
