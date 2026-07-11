#Requires -Modules Pester

Describe "Manifest Completeness" {
	<#
	.SYNOPSIS
		Verifies that every .ps1 file in each module's Functions/ directory is listed in the module manifest's FunctionsToExport.

	.DESCRIPTION
		For each module directory under Modules/, loads the .psd1 manifest and compares
		FunctionsToExport against the .ps1 filenames on disk. Fails if any function file
		is missing from FunctionsToExport. The fork-owned Custom area (Modules/Custom) is checked
		too: its mirror-payload functions must appear in Custom.psd1 (empty/absent on a
		pure-upstream setup, so that case trivially passes).
	#>

	BeforeAll {
		$ModulesRoot = (Get-RepositoryPath).Modules
		$ModuleDirs = Get-ChildItem -Path $ModulesRoot -Directory |
			Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).psd1") }
	}

	Context "Each module manifest exports all on-disk functions" {
		It "Module '<_>' exports every function in its Functions/ directory" -ForEach @(
			'Application', 'Bootstrap', 'Configuration', 'Git', 'Helper',
			'Logging', 'System', 'Tests', 'Window', 'Workflow'
		) {
			$moduleName = $_
			$moduleDir = Join-Path -Path $ModulesRoot -ChildPath $moduleName
			$manifestPath = Join-Path -Path $moduleDir -ChildPath "$moduleName.psd1"
			$functionsDir = Join-Path -Path $moduleDir -ChildPath "Functions"

			$manifestPath | Should -Exist -Because "manifest must exist for module $moduleName"
			$functionsDir | Should -Exist -Because "Functions/ directory must exist for module $moduleName"

			$manifest = Import-PowerShellDataFile -Path $manifestPath
			$exported = $manifest.FunctionsToExport

			$diskFunctions = Get-ChildItem -Path $functionsDir -Filter "*.ps1" |
				Select-Object -ExpandProperty BaseName

			foreach ($fn in $diskFunctions) {
				$fn | Should -BeIn $exported -Because "Function '$fn' in $moduleName/Functions/ must appear in $moduleName.psd1 FunctionsToExport"
			}
		}
	}

	Context "Custom area manifest exports all fork functions" {
		It "Custom.psd1 exports every mirror-payload function on disk" {
			$customPath = Join-Path -Path $ModulesRoot -ChildPath "Custom"
			if (-not (Test-Path -Path $customPath)) {
				Set-ItResult -Skipped -Because "no Custom area is present (pure-upstream setup)"
				return
			}

			$customExported = @((Import-PowerShellDataFile -Path (Join-Path $customPath "Custom.psd1")).FunctionsToExport)

			foreach ($sub in (Get-ChildItem -Path $customPath -Directory)) {
				# Skip whole fork modules (they carry their own manifest); check mirror payloads.
				if (Test-Path -Path (Join-Path $sub.FullName "$($sub.Name).psd1")) { continue }
				$functionsDir = Join-Path -Path $sub.FullName -ChildPath "Functions"
				if (-not (Test-Path -Path $functionsDir)) { continue }

				$diskFunctions = Get-ChildItem -Path $functionsDir -Filter "*.ps1" |
					Select-Object -ExpandProperty BaseName
				foreach ($fn in $diskFunctions) {
					$fn | Should -BeIn $customExported -Because "Custom/$($sub.Name)/Functions/$fn.ps1 must appear in Custom.psd1 FunctionsToExport"
				}
			}
		}
	}
}
