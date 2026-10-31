# Starts the Gemini web gateway hidden, once. Copy it next to gemini-web2api.exe (the run directory, outside the repo)
# and register it for login with scripts/windows/register-login-start.ps1 (or the commands in docs/WINDOWS_GATEWAY.md).
# Logs go to data\logs\gemini-web2api.log (rotated by the program itself).
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $dir 'gemini-web2api.exe'

# Do not start a second copy (the port would be taken and the new process would exit with an error).
$running = Get-Process -Name 'gemini-web2api' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $exe }
if ($running) { exit 0 }

Start-Process -FilePath $exe -ArgumentList '--open-ui=false' -WorkingDirectory $dir -WindowStyle Hidden
