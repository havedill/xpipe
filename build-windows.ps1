<#
.SYNOPSIS
Builds XPipe for Windows 11 using the standard Gradle dist task.

.DESCRIPTION
This script builds XPipe for Windows 11. It handles Java detection and path issues,
then uses the standard Gradle 'dist' task as documented in CONTRIBUTING.md.

.PARAMETER Clean
If specified, cleans the build before building. Default is $true.

.PARAMETER BuildType
The type of build to perform. Default is 'dist'. Use 'msi' to build MSI installer (requires private_files.txt).

.EXAMPLE
.\build-windows.ps1
Builds XPipe for Windows using the standard dist task.

.EXAMPLE
.\build-windows.ps1 -Clean $false
Builds without cleaning first.

.EXAMPLE
.\build-windows.ps1 -BuildType msi
Builds the MSI installer (requires private_files.txt).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [bool]
    $Clean = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet('dist', 'msi')]
    [string]
    $BuildType = 'dist'
)

 $ErrorActionPreference = "Stop"

# Colors for output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-ErrorMsg { Write-Host $args -ForegroundColor Red }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

Write-Success "=== XPipe Windows 11 Build Script ==="
Write-Host ""

# Check for required dependencies
Write-Info "Checking dependencies..."

# Check Java
 $javaCmd = Get-Command java -ErrorAction SilentlyContinue
if (-not $javaCmd) {
    Write-ErrorMsg "Error: Java is not installed or not in PATH."
    Write-Warning "  Please install JDK 25 using: winget install Microsoft.OpenJDK.25"
    Write-Warning "  Or manually add Java to your PATH"
    exit 1
}


# Check for javac (JDK compiler)
 $javacCmd = Get-Command javac -ErrorAction SilentlyContinue
if (-not $javacCmd) {
    Write-ErrorMsg "Error: JDK is not fully installed. Only JRE found."
    Write-Warning "  The Java compiler (javac) is missing. Please install the full JDK:"
    Write-Warning "  winget install Microsoft.OpenJDK.25"
    exit 1
}

# Handle Java paths with spaces (Gradle requirement)
 $javaHome = $env:JAVA_HOME
if (-not $javaHome) {
    # Try to find JAVA_HOME from java command
    $javaExe = $javaCmd.Source
    $javaHome = Split-Path (Split-Path $javaExe -Parent) -Parent
}

if ($javaHome -and $javaHome.Contains(' ')) {
    Write-Warning "[WARN] Java path contains spaces: $javaHome"
    Write-Warning "Gradle does not support Java paths with spaces."
    Write-Warning ""
    Write-Warning "Please create a junction (run PowerShell as Administrator):"
    Write-Warning "  New-Item -ItemType Junction -Path 'C:\jdk-25' -Target '$javaHome'"
    Write-Warning ""
    Write-Warning "Then set:"
    Write-Warning "  `$env:JAVA_HOME = 'C:\jdk-25'"
    Write-Warning "  `$env:PATH = 'C:\jdk-25\bin;' + `$env:PATH"
    exit 1
}

# Set Gradle Java home if JAVA_HOME is set
if ($javaHome) {
    $env:GRADLE_OPTS = "-Dorg.gradle.java.home=$javaHome $env:GRADLE_OPTS"
    Write-Success "[OK] Setting Gradle Java home: $javaHome"
}

# Check Gradle
 $gradleCmd = ".\gradlew"
if (-not (Test-Path "gradlew.bat")) {
    Write-ErrorMsg "Error: Gradle wrapper (gradlew.bat) not found."
    Write-Warning "  Please run this script from the XPipe project root directory."
    exit 1
}
Write-Success "[OK] Gradle wrapper found"

Write-Host ""

# Build the project using standard Gradle commands
Write-Success "Building XPipe for Windows..."
Write-Host ""

# Clean if requested
if ($Clean) {
    Write-Info "Cleaning previous build..."
    $ErrorActionPreference = "Continue"
    $cleanResult = & $gradleCmd clean --no-daemon 2>&1
    $ErrorActionPreference = "Stop"
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Clean failed"
        exit 1
    } elseif ($null -eq $LASTEXITCODE -and -not $?) {
        Write-ErrorMsg "Clean failed"
        exit 1
    }
    Write-Host ""
}

# Apply code formatting (Spotless)
Write-Info "Applying code formatting..."
 $spotlessResult = & $gradleCmd spotlessApply --no-daemon 2>&1
if ($?) {
    Write-Success "[OK] Code formatting applied"
} else {
    Write-Warning "[WARN] Code formatting check skipped or failed"
}
Write-Host ""

# Build using the standard dist task (as documented in CONTRIBUTING.md)
Write-Info "Building Windows executable (this may take a while)..."
Write-Info "Using standard Gradle '$BuildType' task as documented in CONTRIBUTING.md"
Write-Host ""

 $buildTask = if ($BuildType -eq 'msi') { ":dist:buildMsi" } else { "dist" }

# Temporarily change ErrorActionPreference to allow warnings without failing
# This prevents harmless jlink warnings from causing the script to exit
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"

# Run the build and capture output
$buildOutput = & $gradleCmd $buildTask --no-daemon 2>&1

# Restore ErrorActionPreference
$ErrorActionPreference = $previousErrorAction

# Display the output (warnings will be shown but won't cause failure)
$buildOutput | ForEach-Object { Write-Host $_ }

# Check the actual exit code (not $? which can be affected by warnings)
# $LASTEXITCODE is set by PowerShell after native command execution
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-ErrorMsg ""
    Write-ErrorMsg "[FAIL] Build failed with exit code $LASTEXITCODE"
    exit 1
} elseif ($null -eq $LASTEXITCODE -and -not $?) {
    # Fallback for older PowerShell versions that don't set $LASTEXITCODE
    # Only fail if $? is false AND we don't have $LASTEXITCODE
    Write-ErrorMsg ""
    Write-ErrorMsg "[FAIL] Build failed"
    exit 1
}

Write-Host ""
Write-Success "=== Build Complete ==="
Write-Host ""
Write-Success "[OK] Windows build completed successfully!"
Write-Host ""
Write-Info "Output location:"
Write-Host "  dist\build\dist\base\"
Write-Host ""
Write-Info "The Windows executable and all required files are in:"
Write-Host "  dist\build\dist\base\"
Write-Host ""

if ($BuildType -eq 'dist') {
    Write-Info "To create an MSI installer (requires private_files.txt):"
    Write-Host "  .\gradlew :dist:buildMsi"
    Write-Host ""
}