# Legacy Doctor â€” Threat Model (Windows v1)

Assets: payload, manifest, keys, restore target integrity, transcripts.
Threats: tampering, silent corruption, wrong-target restore, key compromise.
Mitigations: checksums, signatures, transcripts, explicit target identity, verify gates.
Out-of-scope: compromised kernel defense, guaranteed recovery without redundancy.