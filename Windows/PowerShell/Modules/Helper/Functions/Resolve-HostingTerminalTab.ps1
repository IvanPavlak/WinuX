function Resolve-HostingTerminalTab {
	<#
	.SYNOPSIS
		Identifies the Windows Terminal window and tab that the current shell is running in.

	.DESCRIPTION
		A flow that closes terminal tabs has to know which one it is standing on, because closing
		that tab mid-run kills the flow. Answering it by taking the first WindowsTerminal process
		picks the wrong window whenever more than one is running - the normal state after an
		-Alongside open - so the hosting window is found by walking up the parent-process chain from
		this process until a WindowsTerminal parent appears.

		The tab within that window is named by WT_PROJECT_TAB when it is set: Open-Terminal writes it
		into every tab it creates, and it survives --suppressApplicationTitle, which stops the window
		title from reflecting anything the shell sets. Otherwise the window title is used, which
		mirrors whichever tab is ACTIVE - this one, whenever the command was typed rather than run
		from a background tab.

		Returns $null when the shell is not hosted by Windows Terminal at all (a bare console, an IDE
		terminal, a scheduled task), which callers should read as "no tab of mine is at risk".

	.OUTPUTS
		[pscustomobject] with Handle, ProcessId and TabTitle, or $null.

	.EXAMPLE
		$own = Resolve-HostingTerminalTab
		if ($own -and $own.TabTitle -eq $candidate) { "this is my own tab - close it last" }
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
		Write-LogDebug " [Resolve-HostingTerminalTab] Could not walk the parent process chain => $($_.Exception.Message)" -Style Warning
		return $null
	}

	if (-not $hostingTerminalPid) {
		return $null
	}

	$hostingWindow = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
			Where-Object { $_.ProcessId -eq $hostingTerminalPid })[0]

	if (-not $hostingWindow) {
		return $null
	}

	$tabTitle = if (-not [string]::IsNullOrWhiteSpace($env:WT_PROJECT_TAB)) {
		[string]$env:WT_PROJECT_TAB
	}
	else {
		[string]$hostingWindow.Title
	}

	return [pscustomobject]@{
		Handle    = [IntPtr]$hostingWindow.Handle
		ProcessId = $hostingTerminalPid
		TabTitle  = $tabTitle
	}
}
