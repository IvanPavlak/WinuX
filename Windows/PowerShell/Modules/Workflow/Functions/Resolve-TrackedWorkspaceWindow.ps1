function Resolve-TrackedWorkspaceWindow {
	<#
	.SYNOPSIS
		Finds the live window a workspace tracker record refers to.

	.DESCRIPTION
		The one resolution ladder shared by Close-Workspace (which windows a teardown closes) and
		Get-WorkspaceOpenProtection (which windows a plain open must leave to a live alongside
		workspace). A record is matched by:

		1. Its exact handle - unambiguous for as long as the window lives (Exact = $true).
		2. The same ProcessId + ProcessName, but only when that process has exactly ONE live window.
		   This is the Electron case: the application recreated its window without restarting.
		   A process hosting several windows (a browser, Windows Terminal) gives no way to tell
		   which of them is the recorded one, so the step is skipped rather than guessing the
		   first - that guess handed another workspace's window to the record.
		3. The same ProcessName + exact Title - the application restarted outright. Two workspaces
		   can hold identically titled windows, so this step carries an accepted false-positive
		   risk that callers guard against where it matters.

		Windows Terminal records are resolved by handle only. All of its windows live in one
		process and never get recreated in place, and their titles ("PowerShell") are generic, so
		steps 2 and 3 could only ever land on some other terminal window. A dead terminal handle
		means the window is gone.

		A record that names no process is never re-resolved: a title alone is not evidence of
		ownership.

	.PARAMETER Record
		The tracker window record (Handle, ProcessId, ProcessName, Title).

	.PARAMETER LiveWindows
		The live windows to search, as returned by Get-WindowHandle.

	.OUTPUTS
		[pscustomobject] with Window (the matched live window) and Exact ($true for a handle
		match, $false for a re-resolution), or $null when the record resolves to nothing.

	.EXAMPLE
		$resolved = Resolve-TrackedWorkspaceWindow -Record $record -LiveWindows $liveWindows
		if ($resolved -and $resolved.Exact) { "still the recorded window" }
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Record,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$LiveWindows
	)

	$liveWindowList = @($LiveWindows | Where-Object { $_ })
	$recordedHandle = [int64]$Record.Handle

	$byHandle = @($liveWindowList | Where-Object { [int64]$_.Handle -eq $recordedHandle })[0]
	if ($byHandle) { return [pscustomobject]@{ Window = $byHandle; Exact = $true } }

	$recordedProcessName = [string]$Record.ProcessName
	if ([string]::IsNullOrWhiteSpace($recordedProcessName)) { return $null }

	# Handle is the only identity a terminal window has - see the description.
	if ($recordedProcessName -eq 'WindowsTerminal') { return $null }

	if ([int64]$Record.ProcessId -gt 0) {
		$sameProcess = @($liveWindowList | Where-Object {
				[int64]$_.ProcessId -eq [int64]$Record.ProcessId -and [string]$_.ProcessName -eq $recordedProcessName
			})
		if ($sameProcess.Count -eq 1) { return [pscustomobject]@{ Window = $sameProcess[0]; Exact = $false } }
	}

	if (-not [string]::IsNullOrWhiteSpace($Record.Title)) {
		$byTitle = @($liveWindowList | Where-Object {
				[string]$_.ProcessName -eq $recordedProcessName -and [string]$_.Title -eq [string]$Record.Title
			})[0]
		if ($byTitle) { return [pscustomobject]@{ Window = $byTitle; Exact = $false } }
	}

	return $null
}
