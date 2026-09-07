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
		'Get-WorkspaceBenchmark',
		'Get-WorkspaceBenchmarkPath',
		'Get-WorkspaceOpenDelta',
		'Get-WorkspaceOpenProtection',
		'Get-WorkspaceState',
		'Get-WorkspaceStatePath',
		'Measure-WorkspaceOpen',
		'Open-DnD',
		'Open-Project',
		'Open-ProjectSwagger',
		'Open-ProjectTerminals',
		'Open-Training',
		'Open-Workspace',
		'Read-WorkspaceBenchmark',
		'Resolve-ProjectDockerCompose',
		'Resolve-SwaggerBrowserGroup',
		'Save-WorkspaceState',
		'Start-Containers',
		'Test-TerminalTabsAlreadyOpen',
		'Training-Backup',
		'Write-WorkspaceBenchmark'
	)
}
