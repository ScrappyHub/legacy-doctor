# Safe Paste

Use this when you are about to paste/run something from the console.
It refuses to run if your clipboard still contains prompts/output (the common `PS ...>` / `DONE` / `HASHES` loop).

## Use
1) Copy ONLY the command block you actually want to execute.
2) Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\safe-paste.ps1
```

3) Then run the clean script it writes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\_clipboard_clean.ps1
```

## If you intentionally copied a script-writing pipeline
Re-run with:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\safe-paste.ps1 -AllowScriptPipelines
```
