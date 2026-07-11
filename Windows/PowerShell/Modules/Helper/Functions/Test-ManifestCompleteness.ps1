function Test-ManifestCompleteness {
	<#
	.SYNOPSIS
		Warns about function files that are not exported by their module manifest.

	.DESCRIPTION
		Startup integrity check. For every module under the WinuX Modules root that ships a
		matching <Name>.psd1 manifest and a Functions/ directory, compares the .ps1 files on disk
		against the manifest's FunctionsToExport list and warns about any function that exists on
		disk but is not registered for export - i.e. a function that "isn't in its corresponding
		module" manifest. The fork-owned Custom area (Modules/Custom) is checked the same way: its
		mirror-payload functions (Custom/<Module>/Functions/*.ps1) must appear in Custom.psd1, and a
		whole fork module (Custom/<Module> with its own manifest) is checked against that manifest.

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

		# The fork-owned Custom area aggregates fork functions from nested mirror payloads
		# (Custom/<Module>/Functions/*.ps1) under a single Custom.psd1, so its layout differs from
		# an engine module and the loop above skips it (no direct Functions/ dir). Check it here:
		# mirror payloads must be in Custom.psd1, and any whole fork module (Custom/<Module> with
		# its own manifest) is checked against that manifest. Absent on a pure-upstream setup.
		$customPath = Join-Path -Path $modulesPath -ChildPath "Custom"
		if (Test-Path -Path $customPath -PathType Container) {
			$customManifest = Join-Path -Path $customPath -ChildPath "Custom.psd1"
			$customExported = if (Test-Path -Path $customManifest) {
				@((Import-PowerShellDataFile -Path $customManifest).FunctionsToExport)
			}
			else { @() }
			$checkedCount++

			foreach ($sub in (Get-ChildItem -Path $customPath -Directory)) {
				$subManifest = Join-Path -Path $sub.FullName -ChildPath "$($sub.Name).psd1"
				$subFunctions = Join-Path -Path $sub.FullName -ChildPath "Functions"
				if (-not (Test-Path -Path $subFunctions)) { continue }

				# Whole fork module -> its own manifest; mirror payload -> Custom.psd1.
				$against = if (Test-Path -Path $subManifest) {
					@((Import-PowerShellDataFile -Path $subManifest).FunctionsToExport)
				}
				else { $customExported }

				foreach ($fn in @(Get-ChildItem -Path (Join-Path $subFunctions "*.ps1") -File |
						Select-Object -ExpandProperty BaseName)) {
					if ($fn -notin $against) {
						$unexported += "Custom\$($sub.Name)\$fn"
					}
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
