function Open-Terminal {
	<#
	.SYNOPSIS
		Opens Windows Terminal with optional command execution and custom tab titles.

	.DESCRIPTION
		Opens Windows Terminal in a new window or in the current shell with support for:
		- Running multiple commands in separate tabs
		- Custom tab titles for better organization
		- Administrator privileges when needed
		- Multiple tabs in the same window or new windows

	.PARAMETER Command
		Array of commands to execute in separate tabs. Each command opens in its own tab.
		Commands are base64-encoded to ensure proper execution.

	.PARAMETER Administrator
		Opens Windows Terminal with administrator privileges.

	.PARAMETER InSameShell
		Opens all tabs in the current Windows Terminal window instead of creating a new window.
		Default: $false (creates a new window)
		The current window is targeted via $env:WT_WINDOW_ID when the calling shell knows its
		own window ID (set by Open-Workspace's -Alongside bootstrap). Without it, window ID 0
		is used - note that "wt -w 0" targets the MOST RECENTLY USED window, which with
		multiple Windows Terminal windows open is not necessarily the caller's window.

	.PARAMETER WindowId
		Specifies an explicit Windows Terminal window ID to open tabs in.
		When provided, this takes precedence over the InSameShell parameter.
		Useful for grouping tabs from different calls into the same window.

	.PARAMETER TabTitles
		Array of custom titles for each tab. Should match the number of commands.
		Tab titles help identify and organize multiple project tabs.

	.EXAMPLE
		Open-Terminal

	.EXAMPLE
		Open-Terminal -Administrator

	.EXAMPLE
		Open-Terminal -Command "git status", "npm run dev"

	.EXAMPLE
		Open-Terminal -Command "Set-Location C:\Projects\API", "Set-Location C:\Projects\UI" -TabTitles "API", "UI" -InSameShell

	.EXAMPLE
		Open-Terminal -Command "docker ps", "kubectl get pods" -TabTitles "Docker", "K8s" -Administrator
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Command,

		[Parameter()]
		[switch]$Administrator,

		[Parameter()]
		[switch]$InSameShell,

		[Parameter()]
		[string]$WindowId,

		[Parameter()]
		[string[]]$TabTitles
	)

	try {
		$PwshPath = Join-Path -Path $PSHOME -ChildPath "pwsh.exe"

		if ($Command.Count -gt 0) {
			# InSameShell prefers the exact window ID when the calling shell knows it
			# (WT_WINDOW_ID, set by Open-Workspace's -Alongside bootstrap): "wt -w 0"
			# targets the MOST RECENTLY USED window, so with multiple Windows Terminal
			# windows open it can land tabs in a different window than the caller's.
			$resolvedWindowId = if ($PSBoundParameters.ContainsKey('WindowId')) {
				$WindowId
			}
			elseif ($InSameShell) {
				if ($env:WT_WINDOW_ID) { $env:WT_WINDOW_ID } else { 0 }
			}
			else {
				[guid]::NewGuid().ToString()
			}
			$StartWT = $false

			for ($i = 0; $i -lt $Command.Count; $i++) {
				$cmd = $Command[$i]

				# If a tab title is specified, set an env var marker for identification and
				# wrap the command in try/finally so the title is restored after Ctrl+C.
				# Long-running commands (e.g., npm run dev) block the trailing title set,
				# but the finally block ensures the title is restored when the process is interrupted.
				if ($TabTitles -and $i -lt $TabTitles.Count) {
					$title = $TabTitles[$i]
					$cmd = "`$env:WT_PROJECT_TAB = '$title'; `$host.UI.RawUI.WindowTitle = '$title'; try { " + $cmd + " } finally { `$host.UI.RawUI.WindowTitle = '$title' }; `$host.UI.RawUI.WindowTitle = '$title'"
				}

				$bytes = [System.Text.Encoding]::Unicode.GetBytes($cmd)
				$encodedCommand = [Convert]::ToBase64String($bytes)

				$wtArgs = @("-w", $resolvedWindowId, "new-tab")

				if ($TabTitles -and $i -lt $TabTitles.Count) {
					$wtArgs += @("--title", $TabTitles[$i], "--suppressApplicationTitle")
				}

				# -NoProfileLoadTime: never show the "Loading personal and system profiles took
				# NNNms" banner in spawned tabs (slower machines/VMs routinely exceed the 500ms
				# threshold that triggers it).
				$wtArgs += @("`"$PwshPath`"", "-NoExit", "-NoProfileLoadTime", "-EncodedCommand", $encodedCommand)

				if (-not $StartWT -and -not $InSameShell) {
					$StartWT = $true
				}

				if ($Administrator) {
					Start-Process wt -ArgumentList $wtArgs -Verb RunAs
				}
				else {
					Start-Process wt -ArgumentList $wtArgs
				}

				# Wait briefly for Windows Terminal to process the new-tab command
				# This prevents race conditions when opening multiple tabs in succession
				Start-Sleep -Milliseconds 25
			}
		}
		else {
			if ($Administrator) {
				Start-Process wt -Verb RunAs
			}
			else {
				Start-Process wt
			}
		}
	}
	catch {
		Write-LogError "Error: [$($_.Exception.Message)]"
	}
}
