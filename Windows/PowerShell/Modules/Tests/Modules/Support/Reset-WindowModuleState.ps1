<#
.SYNOPSIS
	Test support: puts the loaded Window module's state back to exactly how a fresh import leaves it.

.DESCRIPTION
	Window test files used to start with `Import-Module Window.psm1 -Force` purely to get clean
	module state - caches, delays, tolerances, tracking sets - which re-dot-sources every function
	file of the module, a second or so per test file. The state a fresh import gives the module is
	what Window\WindowModuleState.ps1 sets up; every other module-scope variable is created later by
	the functions themselves, always as $script:<Name>.

	Reset-WindowModuleState therefore removes every $script: variable the module's own files assign
	or read, and then runs WindowModuleState.ps1 inside the module, which is exactly the state a
	fresh import would start from - without reloading a single function.

	Dot-source this file from a test's BeforeAll (it defines the function in the test's scope), then
	call Reset-WindowModuleState wherever the file used to re-import the module.
#>

function Reset-WindowModuleState {
	<#
	.SYNOPSIS
		Resets the Window module's script-scope state to its freshly imported values.
	#>
	$windowModule = Get-Module -Name Window | Select-Object -First 1
	if (-not $windowModule) {
		Import-Module -Name (Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1") -Global -WarningAction SilentlyContinue
		return
	}

	$moduleRoot = $windowModule.ModuleBase
	$names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	$files = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File -Include '*.ps1', '*.psm1' -ErrorAction SilentlyContinue)
	foreach ($file in $files) {
		foreach ($match in [regex]::Matches([System.IO.File]::ReadAllText($file.FullName), '\$script:([A-Za-z_][A-Za-z0-9_]*)')) {
			[void]$names.Add($match.Groups[1].Value)
		}
	}

	& $windowModule {
		param([string[]]$VariableNames, [string]$StatePath)
		foreach ($name in $VariableNames) {
			Remove-Variable -Name $name -Scope Script -Force -ErrorAction SilentlyContinue
		}
		. $StatePath
	} @($names) (Join-Path $moduleRoot 'WindowModuleState.ps1')
}
