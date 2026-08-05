function Get-TerminalTabSnapshot {
	<#
	.SYNOPSIS
		Captures the tab titles of every open Windows Terminal window, keyed by window handle.

	.DESCRIPTION
		Terminal tabs are not top-level windows, so a before/after diff of window handles cannot see
		them: opening three project tabs in an existing window changes no handle at all. This walks
		every Windows Terminal window and reads its tab strip through Get-WindowsTerminalTabTitles
		(UI Automation - no focus change, no synthesized keystrokes), producing a snapshot that two
		calls can be differenced against to learn which tabs a flow actually created.

		Windows whose tabs cannot be read are omitted entirely rather than recorded with no tabs.
		Get-WindowsTerminalTabTitles returns $null (never an empty array) for exactly that case, and
		an empty entry would make every one of that window's tabs look newly created the next time
		the snapshot is differenced.

		A terminal is unreadable whenever its virtual desktop is not the visible one: Windows
		Terminal composes its tab strip only while the desktop is on screen. That is the normal state
		at the end of a workspace open, because the layout pass has just moved the terminal onto one
		of the workspace's own desktops - so a snapshot taken then sees nothing, records no tabs, and
		the workspace's terminal tabs become untrackable. -EnsureVisible closes that hole by briefly
		bringing an unreadable terminal's desktop up and putting the view back afterwards. It costs a
		desktop switch, so callers that only need whatever is readable right now should leave it off.

	.PARAMETER EnsureVisible
		Bring an unreadable terminal's virtual desktop on screen long enough to read its tabs, then
		restore whichever desktop was showing to begin with. Terminals already on screen are read
		without switching anything.

	.OUTPUTS
		[hashtable] window handle (Int64) -> [string[]] tab titles in tab-strip order. Empty when
		Windows Terminal is not running.

	.EXAMPLE
		$before = Get-TerminalTabSnapshot
		Open-Project MyProject
		$after = Get-TerminalTabSnapshot
		# Titles present in $after beyond their count in $before are the tabs the open created.

	.EXAMPLE
		$after = Get-TerminalTabSnapshot -EnsureVisible
		# Reads terminals the workspace layout has already parked on other virtual desktops.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[switch]$EnsureVisible
	)

	$snapshot = @{}
	$restoreDesktopIndex = $null

	try {
		foreach ($terminalWindow in @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)) {
			if (-not $terminalWindow) { continue }

			$handle = [IntPtr]$terminalWindow.Handle
			if ($handle -eq [IntPtr]::Zero) { continue }

			$titles = Get-WindowsTerminalTabTitles -WindowHandle $handle

			if ($null -eq $titles -and $EnsureVisible -and (Get-Command Ensure-DesktopVisible -ErrorAction SilentlyContinue)) {
				$previousDesktop = Ensure-DesktopVisible -WindowHandle $handle
				if ($null -ne $previousDesktop -and $null -eq $restoreDesktopIndex) {
					$restoreDesktopIndex = $previousDesktop
				}

				$titles = Get-WindowsTerminalTabTitles -WindowHandle $handle
			}

			# $null means "could not read them", which is not the same answer as "this window has no
			# tabs" - skip the window so the diff never invents tabs that were always there.
			if ($null -eq $titles) { continue }

			$snapshot[$handle.ToInt64()] = @($titles)
		}
	}
	finally {
		# Put the view back even if a read threw: leaving the caller on a desktop it never asked for
		# would be a far worse outcome than a missing tab record.
		if ($null -ne $restoreDesktopIndex) {
			[void](Ensure-DesktopVisible -DesktopIndex $restoreDesktopIndex)
		}
	}

	return $snapshot
}
