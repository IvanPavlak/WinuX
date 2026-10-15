function Resolve-HostingTerminalTab {
	<#
	.SYNOPSIS
		Identifies the Windows Terminal window and tab that the current shell is running in.

	.DESCRIPTION
		A flow that closes terminal tabs has to know which one it is standing on, because closing
		that tab mid-run kills the flow, and a flow that opens tabs "in this window" has to know which
		window that is. Answering it by taking the first WindowsTerminal window picks the wrong one
		whenever more than one is open, so the hosting terminal is found by walking up the
		parent-process chain from this process until a WindowsTerminal parent appears.

		That narrows the answer to a process, not a window: current Windows Terminal versions host
		EVERY window in one WindowsTerminal process, so all of them share the process ID. When the
		hosting process has more than one window, the shell's own window is told apart in two steps:

		  1. WT_PROJECT_TAB (set by Open-Terminal in every tab it creates): the window whose title -
		     its active tab - is exactly that title, when exactly one window has it. A tab opened
		     with --suppressApplicationTitle cannot retitle itself, so this is the only way for it.
		  2. A title probe: a unique marker is written to this shell's console title, the window
		     whose title shows it is this one (the window title mirrors the ACTIVE tab, which is this
		     tab whenever the command was typed), and the original title is restored. The probe waits
		     at most 500 ms for Windows Terminal to reflect the marker.

		When neither identifies a window the first one is returned as before, and Exact is $false so a
		caller that would act on the wrong window can tell it is a guess.

		The tab within that window is named by WT_PROJECT_TAB when it is set: it survives
		--suppressApplicationTitle, which stops the window title from reflecting anything the shell
		sets. Otherwise the shell's own title is used.

		Returns $null when the shell is not hosted by Windows Terminal at all (a bare console, an IDE
		terminal, a scheduled task), which callers should read as "no tab of mine is at risk".

	.OUTPUTS
		[pscustomobject] with Handle, ProcessId, TabTitle and Exact, or $null. Exact is $true when the
		window was identified (the only window of the hosting process, the one window showing
		WT_PROJECT_TAB, or the window that reflected the title probe) and $false when it is the first
		of several windows taken as a fallback.

	.EXAMPLE
		$own = Resolve-HostingTerminalTab
		if ($own -and $own.TabTitle -eq $candidate) { "this is my own tab - close it last" }

	.EXAMPLE
		$own = Resolve-HostingTerminalTab
		if ($own -and $own.Exact) { [void](Confirm-WindowForeground -WindowHandle $own.Handle) }
		Activates this shell's own window, but only when it was identified rather than guessed.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	$hostingTerminalPid = $null

	try {
		$walkProcess = Get-Process -Id $PID -ErrorAction Stop

		# 16 is well past any real shell nesting and stops a cycle from spinning forever.
		for ($i = 0; $i -lt 16 -and $walkProcess; $i++) {
			$parentProcess = $walkProcess.Parent
			if (-not $parentProcess) { break }

			if ($parentProcess.ProcessName -eq 'WindowsTerminal') {
				$hostingTerminalPid = [int]$parentProcess.Id
				break
			}

			$walkProcess = $parentProcess
		}
	}
	catch {
		Write-LogDebug "Could not walk the parent process chain => $($_.Exception.Message)" -Style Warning
		return $null
	}

	if (-not $hostingTerminalPid) {
		return $null
	}

	$hostingWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
			Where-Object { $_.ProcessId -eq $hostingTerminalPid })

	if ($hostingWindows.Count -eq 0) {
		return $null
	}

	$projectTab = if (-not [string]::IsNullOrWhiteSpace($env:WT_PROJECT_TAB)) { [string]$env:WT_PROJECT_TAB } else { $null }
	$hostingWindow = $null
	$exact = $false
	$ownTitle = $null

	if ($hostingWindows.Count -eq 1) {
		$hostingWindow = $hostingWindows[0]
		$exact = $true
	}
	else {
		# Step 1: a project tab's fixed title, when exactly one window shows it.
		if ($projectTab) {
			$titledWindows = @($hostingWindows | Where-Object { $_.Title -eq $projectTab })
			if ($titledWindows.Count -eq 1) {
				$hostingWindow = $titledWindows[0]
				$exact = $true
			}
		}

		# Step 2: the title probe. The poll records what it found in a table rather than in a local:
		# Wait-Until runs the condition in a child scope, where a plain assignment would be lost.
		if (-not $hostingWindow) {
			$probe = "HostingTab_" + [guid]::NewGuid().ToString()
			$probeResult = @{ Window = $null }
			$originalTitle = $null

			try {
				$originalTitle = $Host.UI.RawUI.WindowTitle
				$Host.UI.RawUI.WindowTitle = $probe

				[void](Wait-Until -TimeoutMs 500 -PollIntervalMs 25 -Condition {
						Clear-WindowCache
						$probeResult.Window = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
								Where-Object { $_.ProcessId -eq $hostingTerminalPid -and $_.Title -like "*$probe*" })[0]
						$null -ne $probeResult.Window
					})
			}
			catch {
				Write-LogDebug "Window title probe failed => $($_.Exception.Message)" -Style Warning
			}
			finally {
				if ($null -ne $originalTitle) {
					try { $Host.UI.RawUI.WindowTitle = $originalTitle } catch {}
				}
			}

			if ($probeResult.Window) {
				$hostingWindow = $probeResult.Window
				$exact = $true
				$ownTitle = $originalTitle
			}
		}

		if (-not $hostingWindow) {
			$hostingWindow = $hostingWindows[0]
			Write-LogDebug "Could not tell which of $($hostingWindows.Count) terminal windows hosts this shell - using the first" -Style Warning
		}
	}

	$tabTitle = if ($projectTab) {
		$projectTab
	}
	elseif ($ownTitle) {
		# The probe found the window while it showed the marker; the tab's real title is the one
		# the probe restored.
		[string]$ownTitle
	}
	else {
		[string]$hostingWindow.Title
	}

	return [pscustomobject]@{
		Handle    = [IntPtr]$hostingWindow.Handle
		ProcessId = $hostingTerminalPid
		TabTitle  = $tabTitle
		Exact     = $exact
	}
}
