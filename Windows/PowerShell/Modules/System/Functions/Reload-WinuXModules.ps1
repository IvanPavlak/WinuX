function Reload-WinuXModules {
	<#
	.SYNOPSIS
		Removes and re-imports all WinuX PowerShell modules.

	.DESCRIPTION
		Scans the `Modules/` directory (and the `Modules/Custom` fork area, when populated) for
		folders containing both a `.psd1` manifest and a `.psm1` loader. Removes any currently
		loaded version and re-imports each module. Folders missing either file are skipped with a
		verbose message - this naturally covers the Custom mirror payload folders (e.g.
		`Custom/Application`), whose function files are loaded by the `Custom` module itself.

	.EXAMPLE
		Reload-WinuXModules
		Reloads every WinuX module, including the Custom area.
	#>
	Write-LogTitle "Reloading WinuX Modules" -BlankLineAfter

	$ModulesPath = Join-Path $PSScriptRoot "..\..\"
	$ModulesPath = (Resolve-Path $ModulesPath).Path

	$ModuleFolders = @(Get-ChildItem -Path $ModulesPath -Directory)

	# Whole fork-owned modules live one level deeper, under Modules\Custom\<ModuleName>.
	$CustomPath = Join-Path $ModulesPath "Custom"
	if (Test-Path $CustomPath) {
		$ModuleFolders += @(Get-ChildItem -Path $CustomPath -Directory)
	}

	foreach ($ModuleFolder in $ModuleFolders) {
		$ModuleName = $ModuleFolder.Name
		$ModuleManifest = Join-Path $ModuleFolder.FullName "$ModuleName.psd1"
		$ModuleScript = Join-Path $ModuleFolder.FullName "$ModuleName.psm1"

		if (-not (Test-Path $ModuleManifest) -or -not (Test-Path $ModuleScript)) {
			Write-Verbose "Skipping [$ModuleName] - missing .psd1 or .psm1"
			continue
		}

		try {
			$WarningPreference = "SilentlyContinue"
			Import-Module -Name $ModuleName -Force -ErrorAction Stop -Global | Out-Null
			if (-not (Test-LogVerbose)) {
				Write-LogSuccess "Reloaded module [$ModuleName]" -NoLeadingNewline
			}
		}
		catch {
			Write-LogError "Failed to reload module [$ModuleName] => $_" -NoLeadingNewline
		}
	}
}
