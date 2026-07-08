function Test-ManifestCompleteness {
	<#
	.SYNOPSIS
		Warns about function files that are not exported by their module manifest.

	.DESCRIPTION
		Startup integrity check. For every module under the WinuX Modules root that ships a
		matching <Name>.psd1 manifest and a Functions/ directory, compares the .ps1 files on disk
		against the manifest's FunctionsToExport list and warns about any function that exists on
		disk but is not registered for export - i.e. a function that "isn't in its corresponding
		module" manifest.

		This is the runtime counterpart of the "Manifest Completeness" Pester test, so manifest
		drift can be surfaced on demand. It prints a single success line when every checked module
		exports all of its functions, or a single warning listing the unexported functions otherwise.

		The Modules root is resolved from MachineSpecificPaths.Projects.Self.Modules.

	.EXAMPLE
		Test-ManifestCompleteness
		Prints a success line when all manifests are complete; otherwise lists each unexported
		function as a single warning, e.g. "Helper\Foo, Window\Bar".
	#>
	[CmdletBinding()]
	param()

	try {
		$modulesPath = $MachineSpecificPaths.Projects.Self.Modules

		if (-not $modulesPath -or -not (Test-Path -Path $modulesPath -PathType Container)) {
			Write-LogError " [Manifest] Modules path not found - cannot verify manifest completeness!"
			return
		}

		$unexported = @()
		$checkedCount = 0

		foreach ($moduleDir in (Get-ChildItem -Path $modulesPath -Directory)) {
			$moduleName = $moduleDir.Name
			$manifestPath = Join-Path -Path $moduleDir.FullName -ChildPath "$moduleName.psd1"
			$functionsDir = Join-Path -Path $moduleDir.FullName -ChildPath "Functions"

			# Only modules that ship both a manifest and a Functions/ directory are checked,
			# matching the Manifest Completeness Pester test.
			if (-not (Test-Path -Path $manifestPath) -or -not (Test-Path -Path $functionsDir)) {
				continue
			}

			$checkedCount++

			$exported = @((Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport)
			$onDisk = @(Get-ChildItem -Path (Join-Path $functionsDir "*.ps1") -File |
					Select-Object -ExpandProperty BaseName)

			foreach ($fn in $onDisk) {
				if ($fn -notin $exported) {
					$unexported += "$moduleName\$fn"
				}
			}
		}

		if ($unexported.Count -gt 0) {
			Write-LogWarning " [Manifest] $($unexported.Count) function(s) on disk but missing from their module manifest => $($unexported -join ', ') - add to the matching <Module>.psd1 to fix!"
		}
		elseif ($checkedCount -gt 0) {
			Write-LogSuccess " [Manifest] All $checkedCount module manifest(s) export every function on disk!"
		}
	}
	catch {
		Write-LogError " [Manifest] Failed to verify manifest completeness: $_" -Exception $_
	}
}
