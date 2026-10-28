@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Machine-global AI coding agent setup: one generic mechanism that vendors and deploys AI artifacts (skills, mods, rules, prompts, agents) into the AI apps a machine uses, on Windows and in WSL, plus Claude Code plugin marketplace registration and the MCP servers of Claude Code and Codex."
	RootModule        = "AI.psm1"
	FunctionsToExport = @(
		'Deploy-AiArtifacts',
		'Deploy-AiMarketplaces',
		'Deploy-AiMcpServers',
		'Get-AiArtifactPlan',
		'Get-AiArtifactRoster',
		'Get-AiSkillDescription',
		'Get-AiSkillManifest',
		'List-AiArtifacts',
		'Resolve-AiArtifactsConfig',
		'Resolve-AiModsPluginDirs',
		'Set-ClaudeSettingsEnv',
		'Set-ClaudeSettingsKey',
		'Test-AiModsCli',
		'Update-AiArtifacts'
	)
}
