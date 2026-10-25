function Deploy-CoreAiRules {
	<#
	.SYNOPSIS
		Deprecated since 1.6.0 (removed in 2.0.0): runs Deploy-AiArtifacts -Kind Rules.

	.DESCRIPTION
		Deploy-CoreAiRules linked AI/Claude/managed-settings.json to
		/etc/claude-code/managed-settings.json inside WSL, while SymbolicLinkMaker linked the rules
		file into every harness through PathTemplates.SymbolicLinks.AI. Rules are one kind of AI
		artifact now: Deploy-AiArtifacts -Kind Rules links the rules item AiArtifacts.Use.Rules
		names - its RULES.md into each app's global instruction file and its managed-settings.json
		variant into Claude Code's managed settings, on Windows and in WSL (the WSL link as root).
		Migration: keep the rules in AI\Rules\own\<Name>\ (RULES.md, managed-settings.json), set
		AiArtifacts.Use.Rules and AiArtifacts.Deploy, drop the PathTemplates.SymbolicLinks.AI
		entries and call Deploy-AiArtifacts.

		Warns once per session, then forwards. The deprecated configuration keys are read and
		mapped by Resolve-AiArtifactsConfig, so a fork that has not migrated keeps working until
		2.0.0. See docs/ai/coreairules.md.

	.EXAMPLE
		Deploy-CoreAiRules
		Warns, then runs Deploy-AiArtifacts -Kind Rules.
	#>

	if (-not $script:AiDeprecationWarnings) { $script:AiDeprecationWarnings = @{} }
	if (-not $script:AiDeprecationWarnings.ContainsKey('Deploy-CoreAiRules')) {
		$script:AiDeprecationWarnings['Deploy-CoreAiRules'] = $true
		Write-LogWarning "Deploy-CoreAiRules is deprecated since 1.6.0 and removed in 2.0.0 - use Deploy-AiArtifacts -Kind Rules (docs/ai/coreairules.md)!"
	}

	Deploy-AiArtifacts -Kind Rules
}
