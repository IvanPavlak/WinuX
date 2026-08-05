@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = ""
	RootModule        = "Bootstrap.psm1"
	FunctionsToExport = @(
		'Bootstrap',
		'DetermineMachineType',
		'Expand-ConfigPaths',
		'Expand-Hashtable',
		'Import-AppCsv',
		'Initialize-Configuration',
		'Install-WinGetPackageManager',
		'Invoke-PersonalSteps',
		'Load-PathConfiguration',
		'Merge-Hashtable',
		'Resolve-BootstrapSteps',
		'Resolve-PackageManagers',
		'Test-MachineTypeScope'
	)
}
