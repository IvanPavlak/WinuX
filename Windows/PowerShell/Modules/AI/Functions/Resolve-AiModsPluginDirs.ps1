function Resolve-AiModsPluginDirs {
	<#
	.SYNOPSIS
		Computes the new CLAUDE_CODE_PLUGIN_DIRS value from the current one and the mods just deployed.

	.DESCRIPTION
		Claude Code loads one plugin per entry of CLAUDE_CODE_PLUGIN_DIRS, a path list in the
		platform's separator (';' on Windows, ':' in WSL and on macOS). Deploy-AiMods owns the
		entries under its harness directory and nothing else, so the merge is:

		  1. Every deployed link path, in the order given.
		  2. Every existing entry NOT under the harness, verbatim and in its original order -
		     plugins the user added by hand (including `~`-prefixed ones) pass through.

		Existing entries under the harness that are not deployed any more are stale links to
		mods that left the repository, and are dropped. Empty entries are dropped and duplicates
		collapse to their first occurrence. With ';' as the separator (Windows) paths compare
		case-insensitively; with any other separator they compare exactly.

		Pure: reads and writes nothing, so the merge is testable on its own and shared by the
		Windows and WSL halves of Deploy-AiMods.

	.PARAMETER Existing
		The current CLAUDE_CODE_PLUGIN_DIRS value, or empty when the key is not set.

	.PARAMETER Deployed
		The link paths Deploy-AiMods just created, one per mod.

	.PARAMETER Harness
		The harness directory the deployed links live in (e.g. C:\Users\You\.claude\mods).

	.PARAMETER Separator
		The path-list separator: ';' for Windows, ':' for WSL and macOS.

	.EXAMPLE
		Resolve-AiModsPluginDirs -Existing "D:\Plugins\other;C:\Users\You\.claude\mods\old" -Deployed "C:\Users\You\.claude\mods\my-mod" -Harness "C:\Users\You\.claude\mods" -Separator ';'
		Returns "C:\Users\You\.claude\mods\my-mod;D:\Plugins\other" - the stale "old" entry is dropped.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter()]
		[AllowEmptyString()]
		[string]$Existing = "",

		[Parameter()]
		[AllowEmptyCollection()]
		[string[]]$Deployed = @(),

		[Parameter(Mandatory)]
		[string]$Harness,

		[Parameter(Mandatory)]
		[char]$Separator
	)

	$comparison = if ($Separator -eq ';') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
	$harnessRoot = $Harness.TrimEnd('\', '/')

	$result = [System.Collections.Generic.List[string]]::new()
	$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::FromComparison($comparison))

	foreach ($entry in @($Deployed)) {
		if ([string]::IsNullOrWhiteSpace($entry)) {
			continue
		}
		if ($seen.Add($entry)) {
			$result.Add($entry)
		}
	}

	$existingEntries = if ($Existing) { $Existing.Split($Separator) } else { @() }
	foreach ($entry in $existingEntries) {
		if ([string]::IsNullOrWhiteSpace($entry)) {
			continue
		}
		$trimmed = $entry.TrimEnd('\', '/')
		$isUnderHarness = $trimmed.Equals($harnessRoot, $comparison) -or
			$trimmed.StartsWith("$harnessRoot\", $comparison) -or
			$trimmed.StartsWith("$harnessRoot/", $comparison)
		if ($isUnderHarness) {
			continue
		}
		if ($seen.Add($entry)) {
			$result.Add($entry)
		}
	}

	return ($result -join $Separator)
}
