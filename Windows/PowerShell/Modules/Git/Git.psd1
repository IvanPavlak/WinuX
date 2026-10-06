@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = ""
	RootModule        = "Git.psm1"
	FunctionsToExport = @(
		'Format-RepositoryUpdateResult',
		'Git-Diff',
		'Git-Obsidian',
		'GitBranch',
		'GitBranchDeleteAndPrune',
		'GitMergeM',
		'GitPull',
		'GitStatus',
		'GitSwitch',
		'Initialize-Repository',
		'Install-Git',
		'Invoke-StartupRepositoryUpdate',
		'Resolve-RepositoryDefaultBranch',
		'Resolve-RepositoryTargets',
		'Test-GitRepository',
		'Update-Repositories',
		'Update-Repository',
		'Update-RepositoryDefaultBranch'
	)
}
