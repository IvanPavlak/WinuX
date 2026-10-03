function Get-AiModRoster {
	<#
	.SYNOPSIS
		Enumerates every Claude Code mod under the mods root, flattened by mod name.

	.DESCRIPTION
		Claude Code loads each mod (a function-hook plugin) from its own folder, so the
		repository's <Root>\<source>\<mod>\.claude-plugin\plugin.json tree has to be flattened
		into one name per mod before it can be linked - and every reading has to flatten it the
		same way. This is that single reading: sources are walked in name order, a folder
		without .claude-plugin\plugin.json is not a mod, and when two sources carry the same mod
		name the first source alphabetically wins.

		Returns:

		  Root        The mods root the roster was read from.
		  Mods        An ordered map of mod name -> @{ Name; Path; Source }, in the order the
		              walk found them (source name, then mod name).
		  Duplicates  One entry per losing name -> @{ Name; Source; KeptFrom }, so a caller can
		              report the collision in its own voice rather than this function writing
		              to the log for everybody.

		A missing root is not an error: it yields an empty roster, which is how a vanilla
		install looks before any mod is added.

	.PARAMETER Root
		The mods root to walk. Defaults to (Resolve-AiModsConfig).Root.

	.EXAMPLE
		(Get-AiModRoster).Mods.Count
		Returns how many distinct mods the repository carries.

	.EXAMPLE
		(Get-AiModRoster -Root "C:\Repo\AI\Mods").Mods['my-mod'].Source
		Returns e.g. "own".
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[string]$Root
	)

	if (-not $Root) {
		$Root = (Resolve-AiModsConfig).Root
	}

	$roster = @{
		Root       = $Root
		Mods       = [ordered]@{}
		Duplicates = @()
	}

	if (-not (Test-Path -Path $Root)) {
		return $roster
	}

	foreach ($sourceDir in (Get-ChildItem -Path $Root -Directory | Sort-Object Name)) {
		foreach ($modDir in (Get-ChildItem -Path $sourceDir.FullName -Directory | Sort-Object Name)) {
			if (-not (Test-Path -Path (Join-Path $modDir.FullName ".claude-plugin\plugin.json"))) {
				continue
			}
			if ($roster.Mods.Contains($modDir.Name)) {
				$roster.Duplicates += @{
					Name     = $modDir.Name
					Source   = $sourceDir.Name
					KeptFrom = $roster.Mods[$modDir.Name].Source
				}
				continue
			}
			$roster.Mods[$modDir.Name] = @{
				Name   = $modDir.Name
				Path   = $modDir.FullName
				Source = $sourceDir.Name
			}
		}
	}

	return $roster
}
