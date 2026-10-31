@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Machine-global AI coding agent setup: one generic mechanism that vendors and deploys AI artifacts (skills, mods, rules, prompts, agents) into the AI apps a machine uses, on Windows and in WSL, plus Claude Code plugin marketplace registration, the MCP servers of Claude Code and Codex, and per-machine AI profiles (Plan pin, ownership guard, sign-in walk)."
	RootModule        = "AI.psm1"
	FunctionsToExport = @(
		'ConvertTo-AiManagedSettings',
		'Deploy-AiArtifacts',
		'Deploy-AiManagedSettings',
		'Deploy-AiMarketplaces',
		'Deploy-AiMcpServers',
		'Get-AiArtifactManifest',
		'Get-AiArtifactPlan',
		'Get-AiArtifactRoster',
		'Get-AiSkillDescription',
		'Get-AiSkillManifest',
		'Initialize-AiProfile',
		'List-AiArtifacts',
		'Resolve-AiArtifactsConfig',
		'Resolve-AiModsPluginDirs',
		'Resolve-AiProfile',
		'Set-ClaudeSettingsEnv',
		'Set-ClaudeSettingsKey',
		'Sync-AiManifestCache',
		'Test-AiModsCli',
		'Test-AiProfile',
		'Update-AiArtifacts'
	)
}
