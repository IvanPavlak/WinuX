@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = ""
	RootModule        = "Workflow.psm1"
	RequiredModules   = @('Helper')
	FunctionsToExport = @(
		'Close-BrowserTabsByPattern',
		'Close-Project',
		'Close-ProjectTerminals',
		'DockerWizard',
		'EfCoreMigrationWizard',
		'Focus-TerminalTab',
		'Get-SwaggerCloseTitlePatterns',
		'Open-DnD',
		'Open-Project',
		'Open-ProjectSwagger',
		'Open-ProjectTerminals',
		'Open-Training',
		'Open-Workspace',
		'Resolve-SwaggerBrowserGroup',
		'Test-TerminalTabsAlreadyOpen',
		'Training-Backup'
	)
}
