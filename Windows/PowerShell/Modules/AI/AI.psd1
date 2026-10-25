@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Machine-global AI coding agent setup: one generic mechanism that vendors and deploys AI artifacts (skills, mods, rules, prompts, agents) into the AI apps a machine uses, on Windows and in WSL, plus Claude Code plugin marketplace registration."
	RootModule        = "AI.psm1"
	FunctionsToExport = @(
		'Deploy-AiArtifacts',
		'Deploy-AiMarketplaces',
		'Deploy-AiMods',
		'Deploy-AiSkills',
		'Deploy-CoreAiRules',
		'Get-AiArtifactPlan',
		'Get-AiArtifactRoster',
		'Get-AiModRoster',
		'Get-AiSkillDescription',
		'Get-AiSkillManifest',
		'Get-AiSkillRoster',
		'List-AiArtifacts',
		'List-Skills',
		'Resolve-AiArtifactsConfig',
		'Resolve-AiModsConfig',
		'Resolve-AiModsPluginDirs',
		'Resolve-AiSkillsConfig',
		'Set-ClaudeSettingsEnv',
		'Set-ClaudeSettingsKey',
		'Test-AiModsCli',
		'Update-AiArtifacts',
		'Update-AiMods',
		'Update-AiSkills'
	)
}
