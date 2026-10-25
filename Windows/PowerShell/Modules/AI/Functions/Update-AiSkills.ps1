function Update-AiSkills {
	<#
	.SYNOPSIS
		Deprecated since 1.6.0 (removed in 2.0.0): runs Update-AiArtifacts.

	.DESCRIPTION
		Update-AiSkills vendored the AiSkills.Sources upstreams into AiSkills.Root. Sources are
		one definition for every kind now: AiArtifacts.Sources entries name per kind the upstream
		folders (Skills, Mods, Rules, Prompts, Agents), and Update-AiArtifacts vendors them into
		<Root>\<Kind>\<source>\. Migration: move each AiSkills.Sources entry to
		AiArtifacts.Sources with Folders renamed to Skills, and call Update-AiArtifacts.

		Warns once per session, then forwards -Source and -Check. AiSkills.Sources entries are
		read as AiArtifacts sources by Resolve-AiArtifactsConfig until 2.0.0, so the same source
		names keep working. See docs/ai/artifacts.md.

	.PARAMETER Source
		Names of the sources to refresh. Defaults to every source.

	.PARAMETER Check
		Report whether each source's vendored copy is behind its upstream Ref, changing nothing.

	.EXAMPLE
		Update-AiSkills -Check
		Warns, then runs Update-AiArtifacts -Check.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Source,

		[Parameter()]
		[switch]$Check
	)

	if (-not $script:AiDeprecationWarnings) { $script:AiDeprecationWarnings = @{} }
	if (-not $script:AiDeprecationWarnings.ContainsKey('Update-AiSkills')) {
		$script:AiDeprecationWarnings['Update-AiSkills'] = $true
		Write-LogWarning "Update-AiSkills is deprecated since 1.6.0 and removed in 2.0.0 - use Update-AiArtifacts (docs/ai/artifacts.md)!"
	}

	$forward = @{ Check = $Check }
	if ($Source) { $forward.Source = $Source }
	Update-AiArtifacts @forward
}
