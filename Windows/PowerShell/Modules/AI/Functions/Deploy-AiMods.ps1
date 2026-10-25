function Deploy-AiMods {
	<#
	.SYNOPSIS
		Deprecated since 1.6.0 (removed in 2.0.0): runs Deploy-AiArtifacts -Kind Mods.

	.DESCRIPTION
		Deploy-AiMods linked every Claude Code mod under AiMods.Root into the AiMods.Harnesses
		folders and listed them in env.CLAUDE_CODE_PLUGIN_DIRS. Mods are one kind of AI artifact
		now: Deploy-AiArtifacts -Kind Mods does both through the claude-plugin-dirs hook of the
		claude-code harness, on Windows and in WSL. Migration: set AiArtifacts.Deploy and call
		Deploy-AiArtifacts.

		Warns once per session, then forwards. The deprecated configuration keys it used to read
		are read and mapped by Resolve-AiArtifactsConfig, so a fork that has not migrated keeps
		working until 2.0.0. See docs/ai/artifacts.md.

	.EXAMPLE
		Deploy-AiMods
		Warns, then runs Deploy-AiArtifacts -Kind Mods.
	#>
	[CmdletBinding()]
	param()

	if (-not $script:AiDeprecationWarnings) { $script:AiDeprecationWarnings = @{} }
	if (-not $script:AiDeprecationWarnings.ContainsKey('Deploy-AiMods')) {
		$script:AiDeprecationWarnings['Deploy-AiMods'] = $true
		Write-LogWarning "Deploy-AiMods is deprecated since 1.6.0 and removed in 2.0.0 - use Deploy-AiArtifacts -Kind Mods (docs/ai/artifacts.md)!"
	}

	Deploy-AiArtifacts -Kind Mods
}
