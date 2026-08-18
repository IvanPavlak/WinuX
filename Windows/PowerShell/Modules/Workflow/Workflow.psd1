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
		'Close-Workspace',
		'Docker-Cleanup',
		'DockerWizard',
		'EfCoreMigrationWizard',
		'Focus-TerminalTab',
		'Format-WorkspaceStateContent',
		'Get-SwaggerCloseTitlePatterns',
		'Get-WorkspaceOpenDelta',
		'Get-WorkspaceState',
		'Get-WorkspaceStatePath',
		'Open-DnD',
		'Open-Project',
		'Open-ProjectSwagger',
		'Open-ProjectTerminals',
		'Open-Training',
		'Open-Workspace',
		'Resolve-ProjectDockerCompose',
		'Resolve-SwaggerBrowserGroup',
		'Save-WorkspaceState',
		'Start-Containers',
		'Test-TerminalTabsAlreadyOpen',
		'Training-Backup'
	)
}
