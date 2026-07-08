function Get-CurrentLayout {
	<#
	.SYNOPSIS
		Reads the persisted CurrentLayout.txt snapshot written by Save-CurrentLayout.

	.DESCRIPTION
		Set-WorkspaceWindowLayout records the result of every successful workspace open
		into Window\Layouts\CurrentLayout.txt - a PowerShell data file (parsed with the
		same Import-PowerShellDataFile used for layout .psd1 files) that captures, per
		open workspace: the virtual desktop count, which FancyZones layout was applied to
		each monitor on each desktop, and one record per window that was positioned and
		snapped (handle, process fingerprint, title, layout-relative desktop, monitor, and
		zone).

		Get-CurrentLayout loads that file and returns either the whole snapshot or a single
		workspace's section. It is read when a workspace is initialized, reopened, or opened
		-Alongside so the placement can be made deterministic for layouts that contain many
		identically-named windows (e.g. several "Browser" entries) - Set-WindowLayouts uses
		the per-zone records as a tiebreaker when geometric matching is ambiguous, and
		Save-CurrentLayout uses the existing sections so an -Alongside open preserves the
		records of the workspaces already on screen.

		The read never throws: a missing, empty, or unparseable file simply returns $null so
		callers transparently fall back to their normal (stateless) behaviour.

	.PARAMETER LayoutsDir
		The Layouts directory that holds CurrentLayout.txt (the value of
		$MachineSpecificPaths.Projects.Self.Layouts).

	.PARAMETER Workspace
		Optional. When supplied, returns only that workspace's section (or $null when the
		snapshot does not contain it). When omitted, the entire parsed snapshot is returned.

	.OUTPUTS
		[hashtable] the parsed snapshot (or the requested workspace section), or $null.

	.EXAMPLE
		$snapshot = Get-CurrentLayout -LayoutsDir $layoutsDir
		# Returns the whole CurrentLayout.txt snapshot, or $null if absent.

	.EXAMPLE
		$section = Get-CurrentLayout -LayoutsDir $layoutsDir -Workspace 'Example_PC'
		# Returns just the Example_PC workspace section.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$LayoutsDir,

		[Parameter()]
		[string]$Workspace
	)

	if ([string]::IsNullOrWhiteSpace($LayoutsDir)) {
		return $null
	}

	$path = Join-Path $LayoutsDir 'CurrentLayout.txt'

	if (-not (Test-Path -Path $path)) {
		return $null
	}

	# Parsing is restricted-language (data only, no code execution) and must never break a
	# workspace open - treat any failure as "no snapshot".
	try {
		$data = Import-PowerShellDataFile -Path $path -ErrorAction Stop
	}
	catch {
		Write-LogDebug " [Get-CurrentLayout] Could not parse CurrentLayout.txt: $($_.Exception.Message)" -Style Warning
		return $null
	}

	if (-not $data) {
		return $null
	}

	if ($Workspace) {
		if ($data.Workspaces -and $data.Workspaces.ContainsKey($Workspace)) {
			return $data.Workspaces[$Workspace]
		}
		return $null
	}

	return $data
}
