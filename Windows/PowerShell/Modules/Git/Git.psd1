@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = ""
	RootModule        = "Git.psm1"
	FunctionsToExport = @(
		'ConvertFrom-UpstreamManifest',
		'Format-RepositoryUpdateResult',
		'Get-RepositoryUpdateDayStart',
		'Get-RepositoryUpdateStartupSettings',
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
		'Invoke-RepositoryUpdatePromptCheck',
		'Invoke-StartupRepositoryUpdate',
		'Merge-Upstreams',
		'Register-RepositoryUpdatePromptCheck',
		'Resolve-RepositoryDefaultBranch',
		'Resolve-RepositoryTargets',
		'Resolve-UpstreamPathClass',
		'Resolve-UpstreamRemote',
		'Restore-RepositoryStash',
		'Set-GitConsoleColor',
		'Test-GitRepository',
		'Test-RepositoryUpdateStampFresh',
		'Update-Repositories',
		'Update-Repository',
		'Update-RepositoryDefaultBranch'
	)
}
