param(
  [switch]$SkipTauri,
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$desktopDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $desktopDir '..\..')).Path

# Prefer the fork-local Node version if it was installed.
$localNode = Join-Path $repoRoot '.local-tools\node22'
if (Test-Path (Join-Path $localNode 'node.exe')) {
  $env:PATH = "$localNode;$env:PATH"
}
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
if (Test-Path (Join-Path $cargoBin 'cargo.exe')) {
  $env:PATH = "$cargoBin;$env:PATH"
}

foreach ($tool in @('node', 'npm')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "$tool was not found. Install Node.js 22 or restore .local-tools\node22."
  }
}

if (-not $SkipTauri) {
  if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw 'Cargo was not found. Install Rust or add %USERPROFILE%\.cargo\bin to PATH.'
  }
  # Tauri builds against the Windows MSVC toolchain, including Windows SDK libraries.
  # Do not depend on the shell having been started by Visual Studio.
  $vsRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio'
  $candidates = @(Get-ChildItem -Path (Join-Path $vsRoot '*\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe') -ErrorAction SilentlyContinue)
  if (-not $candidates) {
    throw 'MSVC x64 linker was not found. Install the Desktop development with C++ workload.'
  }
  $link = $candidates | Sort-Object FullName -Descending | Select-Object -First 1
  $binDir = $link.Directory.FullName
  $msvcDir = (Resolve-Path (Join-Path $binDir '..\..\..')).Path
  $sdkRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10'
  $sdkVersions = @(Get-ChildItem -Path (Join-Path $sdkRoot 'Lib') -Directory -ErrorAction SilentlyContinue | Where-Object {
    (Test-Path (Join-Path $_.FullName 'ucrt\x64\ucrt.lib')) -and (Test-Path (Join-Path $_.FullName 'um\x64\kernel32.lib'))
  })
  if (-not $sdkVersions) {
    throw 'Windows SDK x64 libraries were not found. Install Windows 10/11 SDK.'
  }
  $sdkVersion = ($sdkVersions | Sort-Object Name -Descending | Select-Object -First 1).Name
  $sdkLib = Join-Path $sdkRoot "Lib\$sdkVersion"
  $sdkInclude = Join-Path $sdkRoot "Include\$sdkVersion"
  $sdkBin = Join-Path $sdkRoot "bin\$sdkVersion\x64"
  $paths = @($binDir, $sdkBin)
  $env:PATH = ($paths -join ';') + ';' + $env:PATH
  $env:LIB = (@(
    (Join-Path $msvcDir 'lib\x64'),
    (Join-Path $sdkLib 'ucrt\x64'),
    (Join-Path $sdkLib 'um\x64')
  ) -join ';')
  $env:INCLUDE = (@(
    (Join-Path $msvcDir 'include'),
    (Join-Path $sdkInclude 'ucrt'),
    (Join-Path $sdkInclude 'shared'),
    (Join-Path $sdkInclude 'um'),
    (Join-Path $sdkInclude 'winrt'),
    (Join-Path $sdkInclude 'cppwinrt')
  ) -join ';')
  $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = $link.FullName
}

if ($Check) {
  Write-Output "Node: $(node --version)"
  Write-Output "npm: $(npm --version)"
  if (-not $SkipTauri) {
    Write-Output "Cargo: $(cargo --version)"
    Write-Output "MSVC: $($link.FullName)"
    Write-Output "Windows SDK: $sdkVersion"
  }
  return
}

$listener = Get-NetTCPConnection -LocalPort 1420 -State Listen -ErrorAction SilentlyContinue
if ($listener) {
  $owners = @($listener | Select-Object -ExpandProperty OwningProcess -Unique)
  $details = foreach ($owner in $owners) {
    $process = Get-Process -Id $owner -ErrorAction SilentlyContinue
    if ($process) { "$($process.ProcessName) (PID $owner)" } else { "PID $owner" }
  }
  throw "Port 1420 is already in use by $($details -join ', '). Close that dev session or inspect it before retrying."
}

Push-Location $desktopDir
try {
  if ($SkipTauri) {
    npm run dev
  } else {
    npm run tauri -- dev
  }
} finally {
  Pop-Location
}