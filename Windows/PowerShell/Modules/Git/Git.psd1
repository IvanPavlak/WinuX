@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = ""
	RootModule        = "Git.psm1"
	FunctionsToExport = @(
		'ConvertFrom-UpstreamManifest',
		'Format-RepositoryUpdateResult',
		'Get-RepositoryHooks',
		'Get-RepositoryHooksState',
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
		'Merge-Upstreams',
		'Resolve-RepositoryDefaultBranch',
		'Resolve-RepositoryTargets',
		'Resolve-UpstreamPathClass',
		'Resolve-UpstreamRemote',
		'Restore-RepositoryStash',
		'Set-GitConsoleColor',
		'Sync-RepositoryHooks',
		'Test-GitRepository',
		'Update-Repositories',
		'Update-Repository',
		'Update-RepositoryDefaultBranch'
	)
}
