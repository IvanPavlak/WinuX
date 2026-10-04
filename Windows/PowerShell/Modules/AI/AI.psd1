@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Machine-global AI coding agent setup: CoreAiRules enforcement, Agent Skills deployment across Claude Code, Codex CLI and Gemini CLI, and Claude Code mods vendoring and deployment, plus plugin marketplace registration."
	RootModule        = "AI.psm1"
	FunctionsToExport = @(
		'Deploy-AiMarketplaces',
		'Deploy-AiMods',
		'Deploy-AiSkills',
		'Deploy-CoreAiRules',
		'Get-AiModRoster',
		'Get-AiSkillDescription',
		'Get-AiSkillManifest',
		'Get-AiSkillRoster',
		'List-Skills',
		'Resolve-AiModsConfig',
		'Resolve-AiModsPluginDirs',
		'Resolve-AiSkillsConfig',
		'Set-ClaudeSettingsEnv',
		'Set-ClaudeSettingsKey',
		'Test-AiModsCli',
		'Update-AiMods',
		'Update-AiSkills'
	)
}
