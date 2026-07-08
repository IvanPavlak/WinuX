#Requires -Modules Pester

Describe "Manifest Completeness" {
	<#
	.SYNOPSIS
		Verifies that every .ps1 file in each module's Functions/ directory is listed in the module manifest's FunctionsToExport.

	.DESCRIPTION
		For each module directory under Modules/, loads the .psd1 manifest and compares
		FunctionsToExport against the .ps1 filenames on disk. Fails if any function file
		is missing from FunctionsToExport.
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
}
