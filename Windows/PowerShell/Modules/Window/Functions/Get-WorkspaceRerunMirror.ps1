function Get-WorkspaceRerunMirror {
	<#
	.SYNOPSIS
		Reads and consumes the persisted mirror of a workspace rerun marker.

	.DESCRIPTION
		Set-WorkspaceWindowLayout tracks its auto-rerun state in process-scoped environment
		variables, which survive the terminal respawn only when Windows Terminal spawns a fresh
		host per `wt` call (windowingBehavior "useNew"). Under "useAnyExisting" the new tab
		inherits the WT host's stale environment instead, resetting every marker and uncapping the
		rerun loop - so each value is additionally mirrored outside the process by
		Set-WorkspaceRerunMirror as "value|unix-timestamp".

		This function reads that mirror back. It is deliberately one-shot: a value found is
		cleared as it is read, so a marker can influence exactly the run it was written for and
		can never leak into a later one. A value older than -TtlMinutes (or timestamped in the
		future, which means a clock change) is discarded, as is anything that does not parse as
		"value|timestamp".

		Returns $null when there is nothing valid to report, which is the normal case.

	.PARAMETER Name
		The environment variable name to read, e.g. WORKSPACE_WINDOW_ONLY_RETRY.

	.PARAMETER TtlMinutes
		Maximum age, in minutes, at which a mirrored value is still honored. Defaults to 10.

	.PARAMETER Scope
		Which environment scope holds the mirror. Defaults to User, which is what survives a
		process being replaced. Process is for tests: it exercises the identical parsing,
		consume-on-read and TTL logic without paying for a User-scope write, which broadcasts
		WM_SETTINGCHANGE to every top-level window and blocks on the slowest to answer.

	.EXAMPLE
		Get-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT'
		Returns the mirrored rerun count if one was written in the last 10 minutes, else $null,
		and clears it either way.

	.EXAMPLE
		Get-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -TtlMinutes 1
		The same, honoring only a value written in the last minute.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Name,

		[Parameter(Mandatory = $false)]
		[int]$TtlMinutes = 10,

		[Parameter(Mandatory = $false)]
		[ValidateSet('User', 'Process')]
		[string]$Scope = 'User'
	)

	$persisted = [Environment]::GetEnvironmentVariable($Name, $Scope)
	if ([string]::IsNullOrEmpty($persisted)) {
		return $null
	}

	# One-shot: consumed on first read, before the value is even validated. An unparseable or
	# expired mirror is exactly as spent as a good one - leaving it behind would mean re-reading
	# and re-discarding it on every subsequent open.
	Set-WorkspaceRerunMirror -Name $Name -Value $null -Scope $Scope

	$parts = $persisted -split '\|', 2
	if ($parts.Count -lt 2) { return $null }

	$timestamp = 0L
	if (-not [long]::TryParse($parts[1], [ref]$timestamp)) { return $null }

	$ageMinutes = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $timestamp) / 60.0
	if ($ageMinutes -gt $TtlMinutes -or $ageMinutes -lt 0) { return $null }

	return $parts[0]
}
