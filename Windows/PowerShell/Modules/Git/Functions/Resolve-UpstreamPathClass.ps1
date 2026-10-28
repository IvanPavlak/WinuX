function Resolve-UpstreamPathClass {
	<#
	.SYNOPSIS
		Decides what a merge from one upstream does with one path: take it, or put it back.

	.DESCRIPTION
		The ownership rule of Merge-Upstreams, as a pure function. The first match wins:

		1. The path is in another upstream's rooms (an own line of another manifest): declined.
		   A merge never writes into the rooms of a project other than the one it merges.
		2. The path is in this upstream's rooms (an own line of its manifest): own, taken.
		3. A take line of the fork's settings adopts the path from this upstream: take, taken.
		4. The path is a mirror file of this upstream's manifest: mirror, taken (every upstream
		   ships the same bytes by contract).
		5. Anything else is the hallway: hallway (taken) when this upstream owns the root,
		   declined otherwise.

		An entry ending in / is a folder and covers every path under it; any other entry is one
		exact file. Paths use forward slashes, as git prints them.

	.PARAMETER Path
		The repository-relative path git reported (forward slashes).

	.PARAMETER Upstream
		The manifest of the upstream being merged (ConvertFrom-UpstreamManifest).

	.PARAMETER Others
		The manifests of the fork's other upstreams.

	.PARAMETER Settings
		The fork's Git/upstreams.local.conf (ConvertFrom-UpstreamManifest), for its take lines.

	.PARAMETER RootOwner
		The upstream that owns the hallway, or 'fork' for none.

	.OUTPUTS
		[string] - own, take, mirror, hallway or declined.

	.EXAMPLE
		Resolve-UpstreamPathClass -Path 'README.md' -Upstream $winux -Others @($foundation) -RootOwner 'fork'
		Returns declined: README.md is in the hallway and the fork owns it.

	.EXAMPLE
		Resolve-UpstreamPathClass -Path 'Windows/CHANGELOG.md' -Upstream $winux -RootOwner 'fork'
		Returns own: Windows/ is one of WinuX's rooms.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[pscustomobject]$Upstream,

		[AllowNull()]
		[object[]]$Others = @(),

		[AllowNull()]
		[pscustomobject]$Settings,

		[AllowNull()]
		[AllowEmptyString()]
		[string]$RootOwner = 'fork'
	)

	# One entry covers a path when it is the same file, or a folder (trailing /) the path is under.
	$covers = {
		param([string]$Entry, [string]$Candidate)
		if ($Entry.EndsWith('/')) { return $Candidate.StartsWith($Entry, [System.StringComparison]::Ordinal) }
		return $Candidate -ceq $Entry
	}

	foreach ($other in @($Others | Where-Object { $_ -and $_.Name -ne $Upstream.Name })) {
		foreach ($entry in @($other.Own)) {
			if (& $covers $entry $Path) { return 'declined' }
		}
	}

	foreach ($entry in @($Upstream.Own)) {
		if (& $covers $entry $Path) { return 'own' }
	}

	if ($Settings) {
		foreach ($take in @($Settings.Take | Where-Object { $_.Upstream -eq $Upstream.Name })) {
			if (& $covers $take.Path $Path) { return 'take' }
		}
	}

	foreach ($entry in @($Upstream.Mirror)) {
		if (& $covers $entry $Path) { return 'mirror' }
	}

	if ($RootOwner -and $RootOwner -eq $Upstream.Name) { return 'hallway' }
	return 'declined'
}
