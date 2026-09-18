function Move-StableWindowEarly {
	<#
	.SYNOPSIS
		Moves a window that just became stable to its layout entry's virtual desktop while the rest of the workspace is still loading.

	.DESCRIPTION
		The OnWindowStable callback of Wait-ForWorkspaceWindows, as a named function. It used to
		be an inline scriptblock in Set-WorkspaceWindowLayout that reached a handful of its
		locals; it now takes the layout pipeline state instead and is testable on its own.

		Desktop relocation is the slowest part of a layout pass, so it overlaps with the windows
		still loading instead of waiting until every one is ready. The move is skipped when the
		entry has no DesktopNumber and when the window is not this open's to claim
		(Pipeline.Claims.TestClaimable): a preserved alongside workspace's window, an existing
		window in alongside mode, or a window a per-desktop pass has already placed and snapped
		(another entry matching it by process - every browser entry matches every browser window
		until the titles resolve - must not carry it off to its own desktop).

		A failing move is swallowed: the pass after the wait moves the window again.

	.PARAMETER Pipeline
		The layout pipeline state (New-WorkspaceLayoutPipelineState): Claims and DesktopOffset.

	.PARAMETER LayoutEntry
		The layout entry the wait matched the window to; its DesktopNumber is 1-based.

	.PARAMETER Window
		The window object (Handle, Title) that became stable.

	.OUTPUTS
		None.

	.EXAMPLE
		$onWindowStable = { param($entry, $window) Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $entry -Window $window }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Pipeline,

		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[object]$LayoutEntry,

		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[object]$Window
	)

	if ($null -eq $LayoutEntry -or $null -eq $Window) { return }
	if ($null -eq $LayoutEntry.DesktopNumber) { return }
	# Not this open's to move: protected, existing in alongside mode, or already placed and
	# snapped by a per-desktop pass.
	if (-not $Pipeline.Claims.TestClaimable($Window.Handle)) { return }

	$internalDesktopIndex = ($LayoutEntry.DesktopNumber - 1) + $Pipeline.DesktopOffset
	try {
		$null = Move-WindowToVirtualDesktop -WindowHandle $Window.Handle -DesktopNumber $internalDesktopIndex
		if (Test-LogVerbose) {
			$displayDesktop = $LayoutEntry.DesktopNumber + $Pipeline.DesktopOffset
			Write-LogDebug "Early move: [$($Window.Title)] => Desktop $displayDesktop" -Style Success
		}
	}
	catch {}
}
