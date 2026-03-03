# Paste Guard

If you copy console text that includes prompts like `PS C:\...>`, PowerShell can misinterpret it (often as `Get-Process`).
This tool strips prompts + obvious output lines and writes a clean runnable script.

## Use
1) Copy the messy console text.
2) Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\paste-guard.ps1
```

3) Then run the cleaned script it writes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\_clipboard_clean.ps1
```
