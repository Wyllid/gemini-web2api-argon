param(
    # Directory that holds gemini-web2api.exe and start-gateway.ps1
    [Parameter(Mandatory = $true)][string]$RunDir,
    [switch]$Remove
)
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$name = 'Gemini-Gateway'
if ($Remove) {
    Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue
    Write-Host "Removed login entry $name"
    return
}
$script = Join-Path (Resolve-Path $RunDir) 'start-gateway.ps1'
if (-not (Test-Path $script)) { throw "start-gateway.ps1 not found in $RunDir" }
$cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
Set-ItemProperty -Path $key -Name $name -Value $cmd
Write-Host "Registered login entry ${name}: $cmd"
