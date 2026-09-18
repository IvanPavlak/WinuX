function New-WindowClaimSet {
	<#
	.SYNOPSIS
		Builds the one object that says which windows a layout pass may claim.

	.DESCRIPTION
		A workspace open decides window ownership from five facts that used to travel as five
		separate parameters through Set-WorkspaceWindowLayout, Wait-ForWorkspaceWindows and
		Set-WindowLayouts, with each function re-deriving what they meant:

		  - Existing   : windows that were on screen before the open started
		  - SkipExisting: whether those are off limits (an -Alongside open adds to a screen other
		                  workspaces are using) or fair game (a plain open owns the screen)
		  - Protected  : windows of alongside workspaces a plain open preserves - never claimed
		  - Excluded   : windows a per-desktop pass already placed and snapped - done, leave alone
		  - Candidates : when set, the ONLY windows a pass may claim (the wait's stable windows) -
		                  a window still loading is never claimed; $null means no such restriction
		  - PinnedMap  : zone key -> the window recorded in the applied layout, for handle pinning

		The two rules every consumer needs are derived here, once:

		  - Test-Claimable(handle): $false when the handle is protected, excluded, existing while
		    SkipExisting is on, or not a candidate while candidates are restricted.
		  - WaitExcluded / WaitPreExisting: what the wait must skip entirely (protected windows,
		    existing windows in alongside mode - they belong to someone else and never match an
		    entry) versus what it counts as stable on first sight (existing windows in plain mode).

		The object is immutable in shape but its sets are live: Set-WorkspaceWindowLayout adds
		each per-desktop pass's placed handles to Excluded as the open progresses.

	.PARAMETER Existing
		Handles of the windows that pre-existed the open.

	.PARAMETER SkipExisting
		Treat the existing windows as another workspace's (alongside mode).

	.PARAMETER Protected
		Handles a plain open preserves (Get-WorkspaceOpenProtection).

	.PARAMETER Excluded
		Handles already placed by a per-desktop pass.

	.PARAMETER Candidates
		When given (even empty), the only handles a pass may claim.

	.PARAMETER PinnedMap
		Zone key -> pinned window record hashtable, or $null.

	.OUTPUTS
		[pscustomobject] Existing, SkipExisting, Protected, Excluded, Candidates (HashSet[IntPtr] or
		$null), HasCandidates, PinnedMap, and the methods Test-Claimable, WaitExcluded, WaitPreExisting.

	.EXAMPLE
		$claims = New-WindowClaimSet -Existing $existingHandles -Protected $protection.WindowHandles
		if ($claims.TestClaimable($window.Handle)) { ... }
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[AllowNull()]
		[object]$Existing,

		[Parameter()]
		[switch]$SkipExisting,

		[Parameter()]
		[AllowNull()]
		[object]$Protected,

		[Parameter()]
		[AllowNull()]
		[object]$Excluded,

		[Parameter()]
		[AllowNull()]
		[object]$Candidates,

		[Parameter()]
		[AllowNull()]
		[hashtable]$PinnedMap
	)

	$toSet = {
		param($Handles)
		$set = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		foreach ($h in @($Handles)) {
			if ($null -eq $h) { continue }
			$value = if ($h -is [IntPtr]) { $h } elseif ($h.PSObject.Properties['Handle']) { [IntPtr][int64]$h.Handle } else { [IntPtr][int64]$h }
			if ($value -ne [IntPtr]::Zero) { [void]$set.Add($value) }
		}
		# The comma keeps the set ONE object: a HashSet returned bare is enumerated by the
		# pipeline, and a one-element set would arrive as a bare IntPtr.
		return , $set
	}

	$hasCandidates = $PSBoundParameters.ContainsKey('Candidates') -and $null -ne $Candidates
	# Built outside the hashtable literal: `if (...) { $set }` as an expression would enumerate
	# the set, and the properties must always be the HashSet itself.
	$candidateSet = $null
	if ($hasCandidates) { $candidateSet = & $toSet $Candidates }
	$claims = [pscustomobject]@{
		Existing      = & $toSet $Existing
		SkipExisting  = [bool]$SkipExisting
		Protected     = & $toSet $Protected
		Excluded      = & $toSet $Excluded
		Candidates    = $candidateSet
		HasCandidates = $hasCandidates
		PinnedMap     = if ($PinnedMap -and $PinnedMap.Count -gt 0) { $PinnedMap } else { $null }
	}

	$claims | Add-Member -MemberType ScriptMethod -Name TestClaimable -Value {
		param([IntPtr]$Handle)
		if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) { return $false }
		if ($this.Protected.Contains($Handle)) { return $false }
		if ($this.Excluded.Contains($Handle)) { return $false }
		if ($this.SkipExisting -and $this.Existing.Contains($Handle)) { return $false }
		if ($this.HasCandidates -and -not $this.Candidates.Contains($Handle)) { return $false }
		return $true
	}
	# What the wait skips entirely: protected windows always, existing windows when they are
	# another workspace's. Waiting a second for a window only to refuse it later hid real
	# shortfalls.
	$claims | Add-Member -MemberType ScriptMethod -Name WaitExcluded -Value {
		$set = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		foreach ($h in $this.Protected) { [void]$set.Add($h) }
		if ($this.SkipExisting) { foreach ($h in $this.Existing) { [void]$set.Add($h) } }
		return , $set
	}
	# What the wait counts as stable on first sight: existing windows a plain open owns. They
	# have nothing to stabilize.
	$claims | Add-Member -MemberType ScriptMethod -Name WaitPreExisting -Value {
		$set = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		if (-not $this.SkipExisting) { foreach ($h in $this.Existing) { [void]$set.Add($h) } }
		return , $set
	}
	# A per-desktop pass narrows the claim set to the wait's stable windows without touching the
	# shared object: same ownership rules, different candidates.
	$claims | Add-Member -MemberType ScriptMethod -Name WithCandidates -Value {
		param($Handles)
		return (New-WindowClaimSet -Existing $this.Existing -SkipExisting:$this.SkipExisting -Protected $this.Protected -Excluded $this.Excluded -Candidates $Handles -PinnedMap $this.PinnedMap)
	}

	return $claims
}
