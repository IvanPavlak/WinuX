# Loader for the fork-owned Custom area (see docs/contributing/fork-model.md - the Custom area).
#
# Aggregates fork-local function files from the mirror payload directories next to this file:
#   Modules/Custom/<Module>/Functions/*.ps1   (e.g. Modules/Custom/Application/Functions)
# Subdirectories that are WHOLE modules (they ship their own <Name>.psd1 + <Name>.psm1) are
# skipped here - they sit on PSModulePath (registered by Load-PathConfiguration) and load
# themselves like any engine module.
#
# Safety rails:
# - A payload file whose name collides with an engine function file of its mirror module is
#   SKIPPED with a warning, so a Custom file can never silently shadow upstream behavior.
# - A payload file that does not define a function matching its file name is reported, since
#   nothing would be exported for it.

$EngineModulesPath = Split-Path -Path $PSScriptRoot -Parent

$Functions = @()
foreach ($PayloadDir in Get-ChildItem -Path $PSScriptRoot -Directory) {
	$PayloadName = $PayloadDir.Name

	# Whole fork-owned modules load themselves via PSModulePath - skip them here.
	if ((Test-Path -Path (Join-Path $PayloadDir.FullName "$PayloadName.psd1")) -and
		(Test-Path -Path (Join-Path $PayloadDir.FullName "$PayloadName.psm1"))) {
		continue
	}

	$FunctionsDir = Join-Path -Path $PayloadDir.FullName -ChildPath "Functions"
	if (-not (Test-Path -Path $FunctionsDir)) {
		continue
	}

	foreach ($File in Get-ChildItem -Path (Join-Path $FunctionsDir "*.ps1") -File) {
		$EngineTwin = Join-Path -Path $EngineModulesPath -ChildPath "$PayloadName\Functions\$($File.Name)"
		if (Test-Path -Path $EngineTwin) {
			Write-Warning "[Custom] Skipped [$PayloadName\$($File.Name)] - the $PayloadName module already ships this function. Reconcile or rename the Custom file."
			continue
		}
		if ($Functions.BaseName -contains $File.BaseName) {
			Write-Warning "[Custom] Skipped [$PayloadName\$($File.Name)] - a Custom function file with this name was already loaded."
			continue
		}
		$Functions += $File
	}
}

foreach ($Function in $Functions) {
	. $Function.FullName

	if (-not (Test-Path -Path "Function:\$($Function.BaseName)")) {
		Write-Warning "[Custom] [$($Function.Name)] did not define a function named [$($Function.BaseName)] - nothing exported for it."
	}
}

$Functions | ForEach-Object {
	$FunctionName = $_.BaseName
	Export-ModuleMember -Function $FunctionName
}
