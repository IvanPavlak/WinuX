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

		All tabs of one call are chained into a single wt invocation
		("new-tab ... ; new-tab ..."): Windows Terminal processes the subcommands of one
		command line strictly in order, which guarantees tab ordering without per-tab
		process spawns and settle sleeps. Batches are split defensively near the Windows
		command-line length limit; follow-up batches target the same window ID.

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
			# Chain every tab into ONE wt invocation ("new-tab ... ; new-tab ..."): Windows
			# Terminal processes subcommands of a single command line strictly in order, so
			# this guarantees tab ordering without the old one-spawn-per-tab + 25ms-sleep
			# pattern (which also raced "wt -w 0" window resolution between spawns).
			# Batches are split defensively when the command line would approach the Windows
			# limit; follow-up batches target the same window ID so they join the same window.
			$maxArgsLength = 24000
			$batchArgs = [System.Collections.Generic.List[string]]::new()
			$batchLength = 0

			$spawnBatch = {
				param([string[]]$ArgsToRun)

				if ($Administrator) {
					Start-Process wt -ArgumentList $ArgsToRun -Verb RunAs
				}
				else {
					Start-Process wt -ArgumentList $ArgsToRun
				}
			}

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

				$tabArgs = [System.Collections.Generic.List[string]]::new()
				$tabArgs.Add("new-tab")

				if ($TabTitles -and $i -lt $TabTitles.Count) {
					$tabArgs.Add("--title")
					$tabArgs.Add($TabTitles[$i])
					$tabArgs.Add("--suppressApplicationTitle")
				}

				# -NoProfileLoadTime: never show the "Loading personal and system profiles took
				# NNNms" banner in spawned tabs (slower machines/VMs routinely exceed the 500ms
				# threshold that triggers it).
				$tabArgs.Add("`"$PwshPath`"")
				$tabArgs.Add("-NoExit")
				$tabArgs.Add("-NoProfileLoadTime")
				$tabArgs.Add("-EncodedCommand")
				$tabArgs.Add($encodedCommand)

				$tabLength = ($tabArgs | Measure-Object -Property Length -Sum).Sum + $tabArgs.Count + 2

				if ($batchArgs.Count -gt 0 -and ($batchLength + $tabLength) -gt $maxArgsLength) {
					& $spawnBatch $batchArgs.ToArray()
					$batchArgs = [System.Collections.Generic.List[string]]::new()
					$batchLength = 0
				}

				if ($batchArgs.Count -eq 0) {
					$batchArgs.Add("-w")
					$batchArgs.Add([string]$resolvedWindowId)
					$batchLength = 32
				}
				else {
					# Standalone ";" separates subcommands within one wt command line.
					$batchArgs.Add(";")
				}

				$batchArgs.AddRange($tabArgs)
				$batchLength += $tabLength
			}

			if ($batchArgs.Count -gt 0) {
				& $spawnBatch $batchArgs.ToArray()
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
