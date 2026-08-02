@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Functions for modifying Configuration.psd1, window layout files, and the machine-local app list overlays"
	RootModule        = "Configuration.psm1"
	RequiredModules   = @()
	FunctionsToExport = @(
		'Find-ConfigurationSection',
		'Test-ConfigurationKeyPath',
		'ConvertTo-ActionString',
		'Add-BrowserGroup',
		'Add-Workspace',
		'Add-Project',
		'Add-SymbolicLink',
		'Add-WindowLayout',
		'Save-AppCsvOverlay',
		'Test-ConfigurationSchema'
	)
}
