function Set-StackedWindowOrder {
	<#
	.SYNOPSIS
		Stacks the windows of several layout entries that share one zone in layout file order.

	.DESCRIPTION
		Several layout entries may place their windows in the SAME zone - typically a fullscreen
		zone holding two titled VS Code windows. The snap pass already raises each window as it
		snaps, in layout order, but a rerun skips windows that are already in place, so the order a
		user left them in would survive. This pass makes the stacking deterministic: within every
		desktop, monitor and zone that holds windows of more than one layout entry, the windows are
		raised in layout order with SetWindowPos (HWND_TOP, no move, no size, no activation), so
		the window of the LAST entry ends on top.

		A zone filled by one entry alone (a single untitled catch-all taking every window of its
		process) is left as it is - the order among those windows is not configured.

	.PARAMETER Results
		The rows Set-WindowLayouts returned. Only Status = Configured rows with a Handle, a
		ZoneName and a LayoutOrder are considered.

	.OUTPUTS
		[int] The number of windows raised.

	.EXAMPLE
		$null = Set-StackedWindowOrder -Results $layoutResults
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyCollection()]
		[AllowNull()]
		[object[]]$Results
	)

	$rows = @($Results | Where-Object {
			$_ -and $_.Status -eq 'Configured' -and $null -ne $_.Handle -and $_.Handle -ne [IntPtr]::Zero -and
			-not [string]::IsNullOrEmpty([string]$_.ZoneName) -and $null -ne $_.LayoutOrder
		})
	if ($rows.Count -lt 2) { return 0 }

	$raised = 0
	$groups = $rows | Group-Object -Property { "$($_.DesktopDisplay)|$($_.MonitorLabel)|$($_.ZoneName)" }
	foreach ($group in $groups) {
		$entryCount = @($group.Group | ForEach-Object { [int]$_.LayoutOrder } | Select-Object -Unique).Count
		if ($entryCount -lt 2) { continue }

		$ordered = @($group.Group | Sort-Object -Property @{ Expression = { [int]$_.LayoutOrder } } -Stable)
		$seen = [System.Collections.Generic.HashSet[IntPtr]]::new()
		foreach ($row in $ordered) {
			$handle = [IntPtr]$row.Handle
			if (-not $seen.Add($handle)) { continue }
			try {
				$flags = [WindowModule.Native]::SWP_NOMOVE -bor [WindowModule.Native]::SWP_NOSIZE -bor [WindowModule.Native]::SWP_NOACTIVATE
				if ([WindowModule.Native]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, 0, 0, $flags)) { $raised++ }
			}
			catch {
				Write-LogDebug " Could not raise [$($row.WindowTitle)] => $($_.Exception.Message)" -Style Warning
			}
		}
		Write-LogDebug " Stacked $($seen.Count) window(s) in [$($group.Name)] in layout order - [$(@($ordered | Select-Object -Last 1).WindowTitle)] on top" -Style Success
	}

	return $raised
}
