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
		'Initialize-Configuration',
		'Install-WinGetPackageManager',
		'Load-PathConfiguration',
		'Merge-Hashtable',
		'Test-MachineTypeScope'
	)
}
