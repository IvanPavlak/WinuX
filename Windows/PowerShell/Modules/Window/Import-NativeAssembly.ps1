<#
.SYNOPSIS
	Loads a C# source file's types, compiling it at most once per source version.

.DESCRIPTION
	Compiling C# with Add-Type costs a few hundred milliseconds in every process that does it -
	every shell, and every test worker, imports the Window module. So the compiled assembly is
	cached on disk, keyed by a hash of the source and the PowerShell version, and every later
	process only loads it, which takes tens of milliseconds.

	The first process after the source changes compiles to a uniquely named file and moves it into
	place, so concurrent first imports cannot clobber each other, and then removes the assemblies of
	superseded sources (one still loaded by a running shell is locked and stays until a later import).
	Any failure on that path - no cache folder, a locked or corrupt file - falls back to the
	in-memory compile, so the cache can only ever make an import faster, never break it.

	A plain script beside Window.psm1, not a function in Functions\: it runs at module import,
	before the function files are dot-sourced, and is not part of the module's interface.

.PARAMETER SourcePath
	The C# source file.

.PARAMETER TypeName
	A type the source defines. When it is already loaded in this process nothing is done.

.PARAMETER CacheDirectory
	Where compiled assemblies are kept. Defaults to %LOCALAPPDATA%\WinuX\NativeCache.

.OUTPUTS
	[pscustomobject] Source ('Loaded' already present, 'Cache' loaded from the cache, 'Compiled'
	compiled into the cache and loaded, 'InMemory' the fallback, 'Missing' no source file),
	AssemblyPath (the cached file, when one was used).

.EXAMPLE
	& (Join-Path $PSScriptRoot 'Import-NativeAssembly.ps1') -SourcePath $nativePath -TypeName 'WindowModule.Native'
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$SourcePath,

	[Parameter(Mandatory = $true)]
	[string]$TypeName,

	[Parameter()]
	[string]$CacheDirectory
)

$isLoaded = { [bool](([System.Management.Automation.PSTypeName]$TypeName).Type) }

if (& $isLoaded) { return [pscustomobject]@{ Source = 'Loaded'; AssemblyPath = $null } }
if (-not (Test-Path -LiteralPath $SourcePath)) { return [pscustomobject]@{ Source = 'Missing'; AssemblyPath = $null } }

$code = Get-Content -LiteralPath $SourcePath -Raw

if (-not $CacheDirectory) {
	$cacheRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [System.IO.Path]::GetTempPath() }
	$CacheDirectory = Join-Path -Path $cacheRoot -ChildPath 'WinuX\NativeCache'
}

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
$source = 'Cache'
$assemblyPath = $null
try {
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try {
		$keyBytes = [System.Text.Encoding]::UTF8.GetBytes($code + "`n" + $PSVersionTable.PSEdition + $PSVersionTable.PSVersion)
		$key = [Convert]::ToHexString($sha.ComputeHash($keyBytes)).Substring(0, 16)
	}
	finally { $sha.Dispose() }
	$assemblyPath = Join-Path -Path $CacheDirectory -ChildPath "$($baseName)_$key.dll"

	if (-not (Test-Path -LiteralPath $assemblyPath)) {
		$source = 'Compiled'
		New-Item -ItemType Directory -Path $CacheDirectory -Force -ErrorAction Stop | Out-Null
		$staging = Join-Path -Path $CacheDirectory -ChildPath "$($baseName)_$key.$PID.dll"
		Add-Type -TypeDefinition $code -Language CSharp -OutputAssembly $staging -OutputType Library -ErrorAction Stop
		try { Move-Item -LiteralPath $staging -Destination $assemblyPath -ErrorAction Stop }
		catch { Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue }

		Get-ChildItem -LiteralPath $CacheDirectory -Filter "$($baseName)_*.dll" -File -ErrorAction SilentlyContinue |
			Where-Object { $_.Name -notlike "$($baseName)_$key*" } |
			Remove-Item -Force -ErrorAction SilentlyContinue
	}

	Add-Type -Path $assemblyPath -ErrorAction Stop
}
catch {
	$source = 'InMemory'
}

if (-not (& $isLoaded)) {
	$source = 'InMemory'
	Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop
}

[pscustomobject]@{
	Source       = $source
	AssemblyPath = $(if ($source -ne 'InMemory') { $assemblyPath })
}
