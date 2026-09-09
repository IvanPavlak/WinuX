@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Machine-global AI coding agent setup: CoreAiRules enforcement and Agent Skills deployment across Claude Code, Codex CLI and Gemini CLI."
	RootModule        = "AI.psm1"
	FunctionsToExport = @(
		'Deploy-AiSkills',
		'Deploy-CoreAiRules',
		'Get-AiSkillDescription',
		'Get-AiSkillManifest',
		'Resolve-AiSkillsConfig',
		'Update-AiSkills'
	)
}
