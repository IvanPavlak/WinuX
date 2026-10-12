function Get-LayoutProcessSiblings {
	<#
	.SYNOPSIS
		Describes how the entries of a layout that share one process relate to each other.

	.DESCRIPTION
		A layout may hold several entries for windows of ONE process - two VS Code folders in two
		zones, or a titled VS Code entry next to an untitled catch-all that takes every other VS Code
		window. Set-WindowLayouts, Wait-ForWorkspaceWindows and Confirm-WorkspaceWindowPositions
		read the same facts from here so the placement, the wait and the verification agree:

		  Shared        - the process has at least two entries whose (ProcessName, WindowTitle) keys
		                  differ. Identical keys are duplicates and keep their own claim logic.
		  Titled        - the entry has a WindowTitle.
		  CatchAll      - Shared and untitled: it takes the windows of the process that no titled
		                  sibling's title matches.
		  SiblingTitles - the WindowTitle patterns of the OTHER titled entries of the process (keys
		                  different from this entry's). A titled entry never falls back to a window
		                  matching one of them, and a catch-all never takes one.
		  BrowserLike   - the process is a browser (the "Browser" token or a browser process name).
		                  Browser entries keep their own title handling in the wait.

		The process key is the ProcessName as written (case-insensitive), so callers pass the
		entries the way they match windows - token-resolved by Resolve-LayoutTokens. A WindowTitle
		of "" or the string '$null' counts as untitled.

	.PARAMETER LayoutConfig
		The layout entries (hashtables or objects with ProcessName / WindowTitle).

	.OUTPUTS
		[pscustomobject[]] One record per entry, in input order: Index, ProcessKey, Key, Titled,
		Shared, CatchAll, BrowserLike, SiblingTitles.

	.EXAMPLE
		$relations = Get-LayoutProcessSiblings -LayoutConfig @(
			@{ ProcessName = 'Code'; WindowTitle = 'MyProject - Visual Studio Code$' }
			@{ ProcessName = 'Code' }
		)
		# $relations[0]: Shared, Titled; $relations[1]: Shared, CatchAll, SiblingTitles = MyProject - Visual Studio Code$
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyCollection()]
		[AllowNull()]
		[object[]]$LayoutConfig
	)

	$titleOf = {
		param($Entry)
		$title = [string]$Entry.WindowTitle
		if ([string]::IsNullOrWhiteSpace($title) -or $title -eq '$null') { return '' }
		return $title
	}

	$entries = @($LayoutConfig)
	$byProcess = @{}
	for ($i = 0; $i -lt $entries.Count; $i++) {
		$entry = $entries[$i]
		if ($null -eq $entry) { continue }
		$processKey = ([string]$entry.ProcessName).ToLowerInvariant()
		if (-not $byProcess.ContainsKey($processKey)) { $byProcess[$processKey] = [System.Collections.Generic.List[int]]::new() }
		$byProcess[$processKey].Add($i)
	}

	$records = [System.Collections.Generic.List[object]]::new()
	for ($i = 0; $i -lt $entries.Count; $i++) {
		$entry = $entries[$i]
		if ($null -eq $entry) {
			$records.Add([PSCustomObject]@{ Index = $i; ProcessKey = ''; Key = ''; Titled = $false; Shared = $false; CatchAll = $false; BrowserLike = $false; SiblingTitles = @() })
			continue
		}
		$processName = [string]$entry.ProcessName
		$processKey = $processName.ToLowerInvariant()
		$title = & $titleOf $entry
		$key = "$processKey|$title"

		$siblingKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
		$siblingTitles = [System.Collections.Generic.List[string]]::new()
		foreach ($siblingIndex in $byProcess[$processKey]) {
			$siblingTitle = & $titleOf $entries[$siblingIndex]
			$siblingKey = "$processKey|$siblingTitle"
			if ($siblingKey -ceq $key) { continue }
			[void]$siblingKeys.Add($siblingKey)
			if ($siblingTitle -and -not $siblingTitles.Contains($siblingTitle)) { $siblingTitles.Add($siblingTitle) }
		}

		$shared = $siblingKeys.Count -gt 0
		$records.Add([PSCustomObject]@{
				Index         = $i
				ProcessKey    = $processKey
				Key           = $key
				Titled        = [bool]$title
				Shared        = $shared
				CatchAll      = $shared -and -not $title
				BrowserLike   = $processName -match '(?i)(browser|firefox|chrome|msedge|brave|chromium)'
				SiblingTitles = $siblingTitles.ToArray()
			})
	}

	return , $records.ToArray()
}
