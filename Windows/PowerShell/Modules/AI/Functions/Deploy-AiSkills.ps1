function Deploy-AiSkills {
	<#
	.SYNOPSIS
		Deprecated since 1.6.0 (removed in 2.0.0): runs Deploy-AiArtifacts -Kind Skills.

	.DESCRIPTION
		Deploy-AiSkills linked every skill under AiSkills.Root into the AiSkills.Harnesses
		folders. Skills are one kind of AI artifact now: Deploy-AiArtifacts -Kind Skills links them
		into the skills destinations of the harnesses AiArtifacts.Deploy names, on Windows and in
		WSL. Migration: set AiArtifacts.Deploy and call Deploy-AiArtifacts.

		Warns once per session, then forwards. The deprecated configuration keys it used to read
		are read and mapped by Resolve-AiArtifactsConfig, so a fork that has not migrated keeps
		working until 2.0.0. See docs/ai/artifacts.md.

	.EXAMPLE
		Deploy-AiSkills
		Warns, then runs Deploy-AiArtifacts -Kind Skills.
	#>
	[CmdletBinding()]
	param()

	if (-not $script:AiDeprecationWarnings) { $script:AiDeprecationWarnings = @{} }
	if (-not $script:AiDeprecationWarnings.ContainsKey('Deploy-AiSkills')) {
		$script:AiDeprecationWarnings['Deploy-AiSkills'] = $true
		Write-LogWarning "Deploy-AiSkills is deprecated since 1.6.0 and removed in 2.0.0 - use Deploy-AiArtifacts -Kind Skills (docs/ai/artifacts.md)!"
	}

	Deploy-AiArtifacts -Kind Skills
}
