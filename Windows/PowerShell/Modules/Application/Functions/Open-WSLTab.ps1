function Open-WSLTab {
	<#
	.SYNOPSIS
		Opens a WSL tab in Windows Terminal, optionally titled and started inside a directory.

	.DESCRIPTION
		Opens a tab on the WSL profile of a distribution - by default the configured
		`DefaultWSLDistribution`, in the current Windows Terminal window, at the distribution's home
		directory, which is the bare `wsl-tab` call.

		The parameters exist for the project tabs. Open-ProjectTerminals and Run-Project both put WSL
		tabs in a project's window, and both used to spawn them themselves - or, in Run-Project's
		case, failed to. This is now the one place that knows how a WSL tab is made.

		-Path starts the tab inside a directory by REPLACING the tab's commandline
		(`wsl.exe -d <distro> --cd <path>`) rather than by setting a starting directory. `wt -d`
		cannot do it: it sets the Win32 working directory of the profile process, so a WSL path is
		rejected outright ("Could not access starting directory"), and even a Windows path would then
		lose to the profile's own `--cd ~`. A commandline given to `new-tab` overrides that profile
		commandline while every other profile setting still applies. The path is passed through
		untranslated because `wsl --cd` takes it as WSL sees it - `/mnt/c/...` for a Windows-mounted
		repository, `/home/...` for a native clone.

		-WindowId targets an explicit Windows Terminal window, the way Open-Terminal's own -WindowId
		does, so a WSL tab joins the same window as the PowerShell tabs opened beside it. Without it
		the tab goes to the caller's window: WT_WINDOW_ID when the shell knows its own window ID,
		otherwise window 0 - which targets the MOST RECENTLY USED window, not necessarily this one.

	.PARAMETER Distribution
		The WSL distribution to open. Defaults to `Configuration.DefaultWSLDistribution`, and the
		call no-ops with a warning when neither is set.

	.PARAMETER Path
		A directory in the distribution's own file system to start the tab in, written as WSL sees
		it. Omitted, the tab opens at the distribution's home directory.

	.PARAMETER TabTitle
		The tab's title. Omitted, Windows Terminal names the tab itself.

	.PARAMETER WindowId
		The Windows Terminal window to open the tab in. Omitted, the caller's window is used.

	.PARAMETER Quiet
		Suppresses the title and success lines, for callers that do their own logging around a batch
		of tabs. The unconfigured-distribution warning is suppressed with them.

	.EXAMPLE
		Open-WSLTab
		Opens a new WSL tab in the current Windows Terminal window, at the distribution's home.

	.EXAMPLE
		Open-WSLTab -Path "/mnt/c/Users/Me/Development/MyProject" -TabTitle "MyProject.WSL" -Quiet
		Opens a titled WSL tab standing in the project, without the log lines - how the project
		terminal flows call it.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string]$Distribution,

		[Parameter()]
		[string]$Path,

		[Parameter()]
		[string]$TabTitle,

		[Parameter()]
		[string]$WindowId,

		[Parameter()]
		[switch]$Quiet
	)

	$distro = if (Test-ConfigValue $Distribution) {
		$Distribution
	}
	else {
		Get-ConfigSetting -Path 'DefaultWSLDistribution'
	}

	if (-not (Confirm-ConfigValue $distro "DefaultWSLDistribution not configured - no WSL tab to open!" -Quiet:$Quiet)) {
		return
	}

	if (-not $Quiet) {
		Write-LogTitle "Opening $distro WSL tab"
	}

	try {
		$targetWindowId = if (Test-ConfigValue $WindowId) {
			$WindowId
		}
		elseif ($env:WT_WINDOW_ID) {
			$env:WT_WINDOW_ID
		}
		else {
			"0"
		}

		$arguments = @("-w", $targetWindowId, "new-tab", "-p", $distro)

		if (Test-ConfigValue $TabTitle) {
			$arguments += @("--title", $TabTitle)
		}

		if (Test-ConfigValue $Path) {
			$arguments += @("wsl.exe", "-d", $distro, "--cd", $Path)
		}

		Start-Process wt -ArgumentList $arguments -WindowStyle Hidden

		# Wait briefly for Windows Terminal to process the new-tab command. This prevents race
		# conditions when several tabs are opened in succession, which is the project-tab case.
		Start-Sleep -Milliseconds 25

		if (-not $Quiet) {
			Write-LogSuccess "$distro WSL tab opened successfully!"
		}
	}
	catch {
		Write-LogError " Error => [$_]"
	}
}
