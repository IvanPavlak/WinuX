function Set-WorkspaceRerunMirror {
	<#
	.SYNOPSIS
		Writes or clears the persisted mirror of a workspace rerun marker.

	.DESCRIPTION
		The write half of the rerun-state mirror that Get-WorkspaceRerunMirror reads. Values are
		stamped as "value|unix-timestamp" so the reader can age them out; see
		Get-WorkspaceRerunMirror for why the mirror exists at all.

		Clearing is read-guarded, and that guard is worth more than it looks. A User-scope
		environment write does not just touch the registry - it broadcasts WM_SETTINGCHANGE to
		every top-level window and blocks on the slowest one to answer, measured at ~700ms on an
		idle desktop and several seconds on a busy one, while the matching read is a plain
		registry lookup at ~2ms. Set-WorkspaceWindowLayout clears these markers on the success
		path of every single workspace open, where the mirror is almost always already absent, so
		writing unconditionally spent most of a second (or more) to achieve nothing. Skipping the
		write when there is nothing to clear leaves the resulting state identical.

		Note that clearing empties the value rather than removing the variable: passing $null from
		PowerShell to [Environment]::SetEnvironmentVariable binds it as an empty string, so the
		entry survives with no content. That is immaterial here - every reader treats empty and
		absent alike - and removing it outright would cost an extra broadcast.

	.PARAMETER Name
		The environment variable name to mirror, e.g. WORKSPACE_WINDOW_ONLY_RETRY.

	.PARAMETER Value
		The value to persist. Empty or $null clears the mirror instead of writing one.

	.PARAMETER Scope
		Which environment scope holds the mirror. Defaults to User, which is what survives a
		process being replaced. Process is for tests: it exercises the identical write and
		clear-guard logic without paying for the WM_SETTINGCHANGE broadcast.

	.EXAMPLE
		Set-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -Value '1'
		Persists "1|<now>" so the respawned shell can read the count back.

	.EXAMPLE
		Set-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -Value $null
		Clears the mirror, and does nothing at all when it is already clear.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Name,

		[Parameter(Mandatory = $false, Position = 1)]
		[AllowEmptyString()]
		[AllowNull()]
		[string]$Value,

		[Parameter(Mandatory = $false)]
		[ValidateSet('User', 'Process')]
		[string]$Scope = 'User'
	)

	if ([string]::IsNullOrEmpty($Value)) {
		if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($Name, $Scope))) {
			[Environment]::SetEnvironmentVariable($Name, $null, $Scope)
		}
		return
	}

	[Environment]::SetEnvironmentVariable($Name, "$Value|$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())", $Scope)
}
