<#
.SYNOPSIS
	Compiles WinuX.ps1 into the double-clickable WinuX.exe installer.

.DESCRIPTION
	Wraps ps2exe (installed on demand, CurrentUser scope) so the executable is always produced
	the same way, locally and in CI. The Release workflow (.github/workflows/release.yml) runs
	this script on every version tag and attaches the result to the GitHub release - the binary
	itself is deliberately NOT committed (Windows/WinuX/WinuX.exe is gitignored), so the release
	assets are its only distribution path.

	ps2exe-produced executables host the Windows PowerShell 5.1 engine - exactly what a fresh
	Windows 11 machine has - which is why WinuX.ps1 is written to stay 5.1-compatible.

.PARAMETER Version
	Product/file version stamped into the executable's version resource. Accepts "1.2.3",
	"v1.2.3", or "1.2.3.4"; normalized to a four-part version. Defaults to 0.0.0.0 (a dev build).

.PARAMETER OutputPath
	Where to write WinuX.exe. Defaults to WinuX.exe next to this script (gitignored, so a local
	build can never land in a commit).

.PARAMETER ChecksumPath
	Optional path for a SHA-256 checksum file ("<hash> *WinuX.exe", sha256sum-compatible).
	The Release workflow publishes it alongside the executable.

.PARAMETER RepoUrl
	Optional repository URL compiled in as the executable's default install source (the
	$DefaultRepoUrl line of WinuX.ps1 is rewritten in a temporary copy before compilation; the
	committed source is never touched). The Release workflow passes the repository it runs in,
	so a fork's executable installs the fork. Omitted, the committed default (public WinuX)
	is compiled in unchanged.

.EXAMPLE
	.\New-WinuXExecutable.ps1

.EXAMPLE
	.\New-WinuXExecutable.ps1 -Version 0.1.0 -ChecksumPath .\WinuX.exe.sha256

.EXAMPLE
	.\New-WinuXExecutable.ps1 -Version 0.1.0 -RepoUrl 'https://github.com/you/YourFork.git'
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $false)]
	[string]$Version = '0.0.0',

	[Parameter(Mandatory = $false)]
	[string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'WinuX.exe'),

	[Parameter(Mandatory = $false)]
	[string]$ChecksumPath,

	[Parameter(Mandatory = $false)]
	[string]$RepoUrl
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# The Win32 version resource ps2exe embeds requires a four-part version - normalize whatever
# was given ("0.1.0", "v0.1.0", a full "0.1.0.0", ...) and fail loudly on anything unparsable.
$normalizedVersion = $Version.TrimStart('v', 'V')
try {
	$parsedVersion = [System.Version]$normalizedVersion
}
catch {
	throw "Version [$Version] is not a valid version number (expected MAJOR.MINOR.PATCH, e.g. 0.1.0)."
}
$fourPartVersion = "{0}.{1}.{2}.{3}" -f $parsedVersion.Major, [Math]::Max(0, $parsedVersion.Minor), [Math]::Max(0, $parsedVersion.Build), [Math]::Max(0, $parsedVersion.Revision)

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
	Write-Host -ForegroundColor DarkCyan "`n[Installing ps2exe module (CurrentUser)]"
	# Windows PowerShell 5.1 may lack the NuGet package provider on a fresh machine/runner and
	# Install-Module would stall on an interactive provider prompt without it.
	if ($PSVersionTable.PSVersion.Major -lt 6 -and -not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
		Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
	}
	Install-Module -Name ps2exe -Force -Scope CurrentUser
}
Import-Module -Name ps2exe -Force

$sourceFile = Join-Path -Path $PSScriptRoot -ChildPath 'WinuX.ps1'
$iconFile = Join-Path -Path $PSScriptRoot -ChildPath 'WinuXLogo.ico'
$inputFile = $sourceFile

if (-not [string]::IsNullOrWhiteSpace($RepoUrl)) {
	# Compile from a temporary copy whose $DefaultRepoUrl points at the requested repository.
	# Locate the assignment by pattern and verify the rewrite actually happened - a silent
	# no-op here would ship an executable that installs the wrong repository.
	$source = Get-Content -Path $sourceFile -Raw
	$defaultUrlMatch = [regex]::Match($source, "(?m)^\`$DefaultRepoUrl = '[^']+'")
	if (-not $defaultUrlMatch.Success) {
		throw "Could not find the `$DefaultRepoUrl assignment in [$sourceFile] - the -RepoUrl rewrite would be a no-op."
	}

	$inputFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "WinuX-$([System.IO.Path]::GetRandomFileName()).ps1"
	$rewritten = $source.Replace($defaultUrlMatch.Value, "`$DefaultRepoUrl = '$RepoUrl'")
	Set-Content -Path $inputFile -Value $rewritten -Encoding utf8

	Write-Host -ForegroundColor DarkCyan "`n[Default repository rewritten for this build]"
	Write-Host -ForegroundColor DarkCyan "   $($defaultUrlMatch.Value) => '$RepoUrl'"
}

try {
	Write-Host -ForegroundColor DarkCyan "`n[Compiling WinuX.exe]"
	Write-Host -ForegroundColor DarkCyan "   Source  => $sourceFile"
	Write-Host -ForegroundColor DarkCyan "   Output  => $OutputPath"
	Write-Host -ForegroundColor DarkCyan "   Version => $fourPartVersion"

	Invoke-ps2exe -inputFile $inputFile -outputFile $OutputPath -iconFile $iconFile `
		-title 'WinuX' -product 'WinuX' -description 'WinuX bootstrap installer' `
		-copyright 'MIT License' -version $fourPartVersion

	if (-not (Test-Path -Path $OutputPath)) {
		throw "ps2exe finished but [$OutputPath] was not created."
	}
}
finally {
	if ($inputFile -ne $sourceFile) {
		Remove-Item -Path $inputFile -Force -ErrorAction SilentlyContinue
	}
}

$hash = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host -ForegroundColor Green "`n=> Built [$OutputPath]"
Write-Host -ForegroundColor DarkCyan "   SHA-256 => $hash"

if (-not [string]::IsNullOrWhiteSpace($ChecksumPath)) {
	# sha256sum-compatible: "<hash> *<filename>" (the asterisk marks binary mode), so the
	# published checksum verifies with sha256sum -c as well as Get-FileHash.
	Set-Content -Path $ChecksumPath -Value "$hash *$(Split-Path -Path $OutputPath -Leaf)" -Encoding ascii
	Write-Host -ForegroundColor DarkCyan "   Checksum => $ChecksumPath"
}
