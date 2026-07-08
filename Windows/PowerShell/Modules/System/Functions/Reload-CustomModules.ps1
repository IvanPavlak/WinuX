function Reload-CustomModules {
	<#
	.SYNOPSIS
		Removes and re-imports all custom PowerShell modules.

	.DESCRIPTION
		Scans the parent `Modules/` directory for folders containing both a `.psd1` manifest
		and a `.psm1` loader. Removes any currently loaded version and re-imports each module.
		Folders missing either file are skipped with a verbose message.

	.EXAMPLE
		Reload-CustomModules
		Reloads all 9 custom modules.
	#>
	Write-LogTitle "Reloading Custom Modules" -BlankLineAfter

	$ModulesPath = Join-Path $PSScriptRoot "..\..\"
	$ModulesPath = (Resolve-Path $ModulesPath).Path

	$ModuleFolders = Get-ChildItem -Path $ModulesPath -Directory
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
