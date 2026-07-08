@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = ""
	RootModule        = "Git.psm1"
	FunctionsToExport = @(
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
		'Update-Repositories'
	)
}
