function Update-AiMods {
	<#
	.SYNOPSIS
		Deprecated since 1.6.0 (removed in 2.0.0): runs Update-AiArtifacts.

	.DESCRIPTION
		Update-AiMods vendored the AiMods.Sources upstreams into AiMods.Root. Sources are one
		definition for every kind now: AiArtifacts.Sources entries name per kind the upstream
		folders (Skills, Mods, Rules, Prompts, Agents), and Update-AiArtifacts vendors them into
		<Root>\<Kind>\<source>\, with the same private-repository token handling. Migration: move
		each AiMods.Sources entry to AiArtifacts.Sources with Folders renamed to Mods (Exclude and
		SkipPaths keep their names), and call Update-AiArtifacts.

		Warns once per session, then forwards -Source and -Check. AiMods.Sources entries are read
		as AiArtifacts sources by Resolve-AiArtifactsConfig until 2.0.0, so the same source names
		keep working. See docs/ai/artifacts.md.

	.PARAMETER Source
		Names of the sources to refresh. Defaults to every source.

	.PARAMETER Check
		Report whether each source's vendored copy is behind its upstream Ref, changing nothing.

	.EXAMPLE
		Update-AiMods -Source my-mod
		Warns, then runs Update-AiArtifacts -Source my-mod.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Source,

		[Parameter()]
		[switch]$Check
	)

	if (-not $script:AiDeprecationWarnings) { $script:AiDeprecationWarnings = @{} }
	if (-not $script:AiDeprecationWarnings.ContainsKey('Update-AiMods')) {
		$script:AiDeprecationWarnings['Update-AiMods'] = $true
		Write-LogWarning "Update-AiMods is deprecated since 1.6.0 and removed in 2.0.0 - use Update-AiArtifacts (docs/ai/artifacts.md)!"
	}

	$forward = @{ Check = $Check }
	if ($Source) { $forward.Source = $Source }
	Update-AiArtifacts @forward
}
