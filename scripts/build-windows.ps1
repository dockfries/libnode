<#
.SYNOPSIS
    Build libnode (Node.js shared library) on Windows.

.DESCRIPTION
    Downloads the Node.js source for a given version, runs vcbuild.bat
    with the shared-library (dll) flag, and places output artifacts
    (libnode.dll, libnode.lib, node.def) into a ./dist/ directory.

.PARAMETER Version
    Node.js version to build (semver, e.g. 22.0.0).

.PARAMETER Arch
    Target architecture: "x64" or "x86".

.PARAMETER UseClangCL
    Switch to enable ClangCL compiler (required for Node.js >= 24).

.PARAMETER NeedRust
    Switch to install/update Rust toolchain (needed for Node.js >= 26).

.EXAMPLE
    .\build-windows.ps1 -Version "22.0.0" -Arch "x64"
    .\build-windows.ps1 -Version "24.18.0" -Arch "x64" -UseClangCL
    .\build-windows.ps1 -Version "22.0.0" -Arch "x86"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [ValidateSet('x64', 'x86')]
    [string]$Arch,

    [switch]$UseClangCL,

    [switch]$NeedRust
)

$ErrorActionPreference = 'Stop'
$SRC_DIR = "node-v$Version"

Write-Host "==> Building libnode for Node.js v$Version (arch: $Arch, clang-cl: $UseClangCL, rust: $NeedRust)"

# ── Install NASM (required for OpenSSL assembly) ────────────────────
if (-not (Get-Command "nasm" -ErrorAction SilentlyContinue)) {
    Write-Host "==> Installing NASM via Chocolatey..."
    choco install nasm --no-progress -y
    # Refresh PATH so nasm is available
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# ── Install/Update Rust if needed (Node.js >= 26) ───────────────────
if ($NeedRust) {
    if (-not (Get-Command "rustup" -ErrorAction SilentlyContinue)) {
        Write-Host "==> Installing Rust toolchain..."
        # rustup-init will be downloaded and run
        $env:RUSTUP_INIT_SKIP_PATH_CHECK = 'yes'
        Invoke-WebRequest -Uri 'https://static.rust-lang.org/rustup/dist/i686-pc-windows-msvc/rustup-init.exe' -OutFile "$env:TEMP\rustup-init.exe"
        & "$env:TEMP\rustup-init.exe" -y --default-toolchain stable --profile minimal --no-modify-path
        # Add Rust to PATH
        $env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
    } else {
        Write-Host "==> Updating Rust toolchain..."
        rustup update
    }
}

# ── Download and extract source ─────────────────────────────────────
$srcArchive = "node-v${Version}.tar.gz"
if (-not (Test-Path $SRC_DIR)) {
    if (-not (Test-Path $srcArchive)) {
        Write-Host "==> Downloading Node.js v$Version source..."
        $url = "https://nodejs.org/dist/v${Version}/node-v${Version}.tar.gz"
        Write-Host "    URL: $url"
        Invoke-WebRequest -Uri $url -OutFile $srcArchive
    }

    Write-Host "==> Extracting source..."
    # GitHub Actions Windows runner has tar; use it with -xf
    tar -xzf $srcArchive
    if (-not (Test-Path $SRC_DIR)) {
        Write-Error "Extraction failed: directory '$SRC_DIR' not found"
        exit 1
    }
}

Push-Location $SRC_DIR

# ── Build with vcbuild.bat ──────────────────────────────────────────
Write-Host "==> Running vcbuild.bat dll release $Arch $(if ($UseClangCL) { 'clang-cl' })..."
$vcbuildArgs = @('dll', 'release', $Arch)
if ($UseClangCL) {
    $vcbuildArgs += 'clang-cl'
}

# Direct invocation — PowerShell invokes cmd.exe under the hood
& .\vcbuild.bat @vcbuildArgs
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Pop-Location
    Write-Error "vcbuild.bat failed with exit code $exitCode"
    exit $exitCode
}

Pop-Location

# ── Collect artifacts ───────────────────────────────────────────────
Write-Host "==> Collecting artifacts..."
$null = New-Item -ItemType Directory -Force -Path "dist"

# The build outputs are placed in a versioned directory by vcbuild.bat
# e.g., node-v22.0.0-win-x64\libnode.dll, or in Release\ directly.
# Search for them.
$foundDll = $false
$searchPaths = @(
    "$SRC_DIR\Release",
    "$SRC_DIR\$SRC_DIR-win-$Arch",
    "$SRC_DIR"
)

foreach ($base in $searchPaths) {
    $dllPath = Join-Path $base "libnode.dll"
    if (Test-Path $dllPath) {
        Write-Host "    Found libnode.dll in $base"
        Copy-Item "$base\libnode.dll" -Destination "dist\"
        if (Test-Path "$base\libnode.lib") {
            Copy-Item "$base\libnode.lib" -Destination "dist\"
        }
        $foundDll = $true
        break
    }
}

if (-not $foundDll) {
    # Fallback: search recursively (slow but thorough)
    Write-Host "    Searching recursively for libnode.dll..."
    $file = Get-ChildItem -Path $SRC_DIR -Recurse -Filter "libnode.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($file) {
        $dir = $file.DirectoryName
        Write-Host "    Found libnode.dll in $dir"
        Copy-Item "$dir\libnode.dll" -Destination "dist\"
        if (Test-Path "$dir\libnode.lib") {
            Copy-Item "$dir\libnode.lib" -Destination "dist\"
        }
        $foundDll = $true
    }
}

if (-not $foundDll) {
    Write-Error "Build completed but libnode.dll was not found!"
    exit 1
}

# ── Package into release archive ────────────────────────────────────
$archiveName = "libnode-windows-$Arch.zip"
Write-Host "==> Packaging artifacts into $archiveName..."
if (Test-Path "dist") {
    Compress-Archive -Path "dist\*" -DestinationPath $archiveName -Force
}
Write-Host "    Created: $archiveName"

Write-Host "==> Build complete! Archive ready: $archiveName"
Get-ChildItem -Path $archiveName

Write-Host "==> Done."
