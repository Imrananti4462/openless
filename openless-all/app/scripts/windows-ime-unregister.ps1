param(
  [ValidateSet("Debug", "Release")]
  [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

function Get-Regsvr32ForPlatform {
  param(
    [ValidateSet("x64", "Win32")]
    [string]$Platform
  )

  if ($Platform -eq "Win32") {
    $syswow64 = Join-Path $env:WINDIR "SysWOW64\regsvr32.exe"
    if (Test-Path $syswow64) {
      return $syswow64
    }
    return (Join-Path $env:WINDIR "System32\regsvr32.exe")
  }

  $sysnative = Join-Path $env:WINDIR "Sysnative\regsvr32.exe"
  if (Test-Path $sysnative) {
    return $sysnative
  }

  return (Join-Path $env:WINDIR "System32\regsvr32.exe")
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Get-DllPath {
  param(
    [ValidateSet("x64", "Win32")]
    [string]$Platform
  )

  $folder = if ($Platform -eq "Win32") { "Win32" } else { $Platform }
  return Join-Path $appRoot "windows-ime\$folder\$Configuration\OpenLessIme.dll"
}

if (-not (Test-IsAdministrator)) {
  throw "Unregistering the OpenLess TSF IME requires an elevated Administrator PowerShell."
}

foreach ($platform in @("x64", "Win32")) {
  $dll = Get-DllPath $platform
  if (-not (Test-Path $dll)) {
    Write-Host "[skip] OpenLessIme.dll not found ($platform): $dll"
    continue
  }

  $regsvr32 = Get-Regsvr32ForPlatform $platform
  $process = Start-Process -FilePath $regsvr32 -ArgumentList @("/u", "/s", $dll) -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "$platform regsvr32 /u failed with exit code $($process.ExitCode)"
  }
  Write-Host "[ok] OpenLess TSF IME unregistered ($platform)"
}
