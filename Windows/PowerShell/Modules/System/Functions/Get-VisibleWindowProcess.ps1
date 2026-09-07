function Get-VisibleWindowProcess {
	<#
	.SYNOPSIS
		Lists every process that owns at least one visible, titled application window.

	.DESCRIPTION
		The discovery step behind Terminate-AllProcessesWithVisibleWindows and the Kill-All
		survivor audit. It answers "which processes have a window on screen" from the window
		side rather than the process side: every visible, titled top-level window is enumerated
		(EnumWindows, through the Window module's Get-CachedWindows) and grouped by owning process.

		That replaces the classic `Get-Process | Where-Object MainWindowTitle` test, which has two
		blind spots that made a cleanup pass skip windows at random:
		  - .NET's MainWindowHandle is the FIRST visible, unowned top-level window of the process
		    in z-order, titled or not. A process whose untitled helper window happens to sit above
		    its real window (Electron and Chromium apps create such windows) reports an empty
		    MainWindowTitle and is skipped - and which window is first depends on focus history,
		    so the same process is sometimes seen and sometimes not.
		  - Windows hosted inside ApplicationFrameHost (packaged / UWP apps) are visible windows
		    of the HOST, while the app's own process reports no main window at all.
		Enumerating the windows sidesteps both: an app is a candidate as soon as any of its
		windows is visible and titled, whatever else the process has open.

		Windows that belong to the shell rather than to an application are ignored: the same
		title list Move-Windows and Center-Windows skip (Program Manager, Windows Input
		Experience, Start, Search, ...) plus the processes that ARE the desktop or merely host
		other apps' windows (explorer, ApplicationFrameHost, TextInputHost, ShellExperienceHost,
		StartMenuExperienceHost, SearchHost, LockApp, sihost, dwm). Killing those either takes the
		desktop down or closes windows the caller never saw.

		When the Window module is not loaded the function falls back to Get-Process and
		MainWindowTitle, with the same shell-process filter, so callers keep working in a
		reduced session; the Source property says which path answered.

	.OUTPUTS
		One object per process: ProcessName, Id, WindowTitles (every visible titled window of the
		process, first-enumerated first), MainWindowTitle (the first of those - the field the
		exclusion matching and the log lines use), Source ('EnumWindows' or 'MainWindowTitle').

	.EXAMPLE
		Get-VisibleWindowProcess | Format-Table ProcessName, Id, MainWindowTitle

	.EXAMPLE
		Get-VisibleWindowProcess | Where-Object { $_.WindowTitles.Count -gt 1 }
		Processes with more than one window on screen.
	#>
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	param()

	# Visible, titled windows the shell owns that are not applications. Mirrors the skip list in
	# Move-Windows / Center-Windows / Resize-Windows.
	$shellWindowTitles = @(
		'Program Manager',
		'Windows Input Experience',
		'TextInputHost',
		'Search',
		'Start',
		'Action center',
		'Microsoft Text Input Application',
		'Windows Shell Experience Host',
		'NVIDIA GeForce Overlay',
		'Setup'
	)

	# Processes that are the desktop itself, or that host other applications' windows. Never
	# cleanup candidates: explorer is the shell, ApplicationFrameHost owns the frames of every
	# packaged app (the apps themselves are enumerated through their own CoreWindow), the rest
	# are Start / Search / input / lock-screen surfaces that Windows restarts on its own.
	$shellProcessNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($name in @('explorer', 'ApplicationFrameHost', 'TextInputHost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'SearchApp', 'LockApp', 'sihost', 'dwm')) {
		$null = $shellProcessNames.Add($name)
	}

	# Plain hashtable plus an explicit order list: an ordered dictionary indexed with an [int]
	# key treats it as a POSITION, so PIDs would throw or hit the wrong entry.
	$byProcess = @{}
	$processOrder = [System.Collections.Generic.List[int]]::new()
	$source = 'EnumWindows'

	$windowModuleAvailable = (Get-Command Get-CachedWindows -ErrorAction SilentlyContinue) -and (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue)
	if ($windowModuleAvailable) {
		# Fresh enumeration: the cache may hold windows a previous step has since closed.
		Clear-WindowCache
		foreach ($window in @(Get-CachedWindows)) {
			if ([string]::IsNullOrEmpty($window.Title) -or $window.Title -in $shellWindowTitles) { continue }
			if ($window.Width -le 0 -or $window.Height -le 0) { continue }
			if ([string]::IsNullOrEmpty($window.ProcessName) -or $shellProcessNames.Contains($window.ProcessName)) { continue }

			$key = [int]$window.ProcessId
			if (-not $byProcess.ContainsKey($key)) {
				$processOrder.Add($key)
				$byProcess[$key] = @{
					ProcessName = $window.ProcessName
					Id          = $key
					Titles      = [System.Collections.Generic.List[string]]::new()
				}
			}
			$byProcess[$key].Titles.Add($window.Title)
		}
	}
	else {
		$source = 'MainWindowTitle'
		foreach ($process in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne '' })) {
			if ($shellProcessNames.Contains($process.ProcessName) -or $process.MainWindowTitle -in $shellWindowTitles) { continue }

			$titles = [System.Collections.Generic.List[string]]::new()
			$titles.Add($process.MainWindowTitle)
			$processOrder.Add([int]$process.Id)
			$byProcess[[int]$process.Id] = @{ ProcessName = $process.ProcessName; Id = [int]$process.Id; Titles = $titles }
		}
	}

	foreach ($key in $processOrder) {
		$entry = $byProcess[$key]
		[PSCustomObject]@{
			ProcessName     = $entry.ProcessName
			Id              = $entry.Id
			WindowTitles    = @($entry.Titles)
			MainWindowTitle = $entry.Titles[0]
			Source          = $source
		}
	}
}
