# Compile native Windows API types once at module load. The compiled assembly is cached on disk,
# so only the first process after WindowNative.cs changes pays for the compile - see
# Import-NativeAssembly.ps1. A missing source file only disables the native optimizations.
$nativePath = Join-Path -Path $PSScriptRoot -ChildPath "WindowNative.cs"
$nativeImport = & (Join-Path -Path $PSScriptRoot -ChildPath "Import-NativeAssembly.ps1") -SourcePath $nativePath -TypeName 'WindowModule.Native'
if ($nativeImport.Source -eq 'Missing') {
	Write-Warning "WindowNative.cs not found at $nativePath - native optimizations disabled"
}

# Opt this process into Per-Monitor-V2 DPI awareness BEFORE any window/monitor API is
# used. FancyZones works in physical pixels; a DPI-unaware process sees virtualized
# coordinates on any display scale above 100%, which silently breaks zone math and snap
# verification. At 100% scaling this changes nothing. No-op (returns false) if the
# process awareness was already fixed by a manifest or an earlier call.
if (([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
	[void][WindowModule.Native]::EnablePerMonitorDpiAwareness()
}

# Module-scoped state (delays, tolerances, caches) - see WindowModuleState.ps1.
. (Join-Path -Path $PSScriptRoot -ChildPath "WindowModuleState.ps1")

$ModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "\Functions"

$Functions = Get-ChildItem -Path (Join-Path $ModulesPath "*.ps1")

foreach ($Function in $Functions) {
	. $Function.FullName
}

$Functions | ForEach-Object {
	$FunctionName = $_.BaseName
	Export-ModuleMember -Function $FunctionName
}
