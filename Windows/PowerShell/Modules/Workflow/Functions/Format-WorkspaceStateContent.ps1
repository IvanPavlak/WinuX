function Format-WorkspaceStateContent {
	<#
	.SYNOPSIS
		Renders tracker entries as the PowerShell data file Get-WorkspaceState reads back.

	.DESCRIPTION
		Emits a literal that round-trips through Import-PowerShellDataFile, so the tracker is
		parsed in restricted language mode (data only, never executed) exactly like the
		repository's layout and configuration .psd1 files.

		Deliberately not a general-purpose serializer. The tracker schema is fixed and entirely
		scalar - strings, integers and booleans in a known shape - so each field is written by name
		with the right conversion. That makes the output predictable, keeps a rogue value from
		silently changing the file's structure, and avoids a second copy of the recursive
		serializer that Save-CurrentLayout carries for its own, differently shaped snapshot.

		Every string is single-quoted with embedded quotes doubled, which is the only escaping a
		PowerShell single-quoted literal needs - window titles routinely contain apostrophes.

	.PARAMETER Entry
		The tracker entries to render. An empty array produces a valid file with no entries, which
		is how a teardown clears the tracker.

	.OUTPUTS
		[string] the full file contents, including the explanatory header.

	.EXAMPLE
		Set-Content -Path $path -Value (Format-WorkspaceStateContent -Entry $entries) -NoNewline
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyCollection()]
		[object[]]$Entry
	)

	$quote = { param($Value) "'" + ([string]$Value -replace "'", "''") + "'" }
	$number = {
		param($Value)
		$parsed = 0L
		if ([int64]::TryParse([string]$Value, [ref]$parsed)) { return [string]$parsed }
		return '0'
	}
	$boolean = { param($Value) if ($Value) { '$true' } else { '$false' } }

	$lines = [System.Collections.Generic.List[string]]::new()

	$lines.Add('# OpenWorkspaces.txt - auto-generated record of what each Open-Workspace invocation opened.')
	$lines.Add('# Written by Save-WorkspaceState after a workspace opens; read by Get-WorkspaceState and')
	$lines.Add('# consumed by Close-Workspace, which closes exactly the windows and terminal tabs listed')
	$lines.Add('# here. Per-machine runtime state - do not edit by hand and do not commit it. Deleting it')
	$lines.Add('# is safe: Close-Workspace then reports that nothing is tracked instead of guessing.')
	$lines.Add('@{')
	$lines.Add("`tEntries = @(")

	foreach ($entryItem in @($Entry)) {
		if (-not $entryItem) { continue }

		$lines.Add("`t`t@{")
		$lines.Add("`t`t`tWorkspace     = $(& $quote $entryItem.Workspace)")
		$lines.Add("`t`t`tAlongside     = $(& $boolean $entryItem.Alongside)")
		$lines.Add("`t`t`tDesktopOffset = $(& $number $entryItem.DesktopOffset)")
		$lines.Add("`t`t`tOpenedUtc     = $(& $quote $entryItem.OpenedUtc)")
		$lines.Add("`t`t`tShellPid      = $(& $number $entryItem.ShellPid)")

		$windows = @($entryItem.Windows | Where-Object { $_ })
		if ($windows.Count -eq 0) {
			$lines.Add("`t`t`tWindows       = @()")
		}
		else {
			$lines.Add("`t`t`tWindows       = @(")
			foreach ($window in $windows) {
				$lines.Add("`t`t`t`t@{ Handle = $(& $number $window.Handle); ProcessId = $(& $number $window.ProcessId); ProcessName = $(& $quote $window.ProcessName); Title = $(& $quote $window.Title) }")
			}
			$lines.Add("`t`t`t)")
		}

		$terminalTabs = @($entryItem.TerminalTabs | Where-Object { $_ })
		if ($terminalTabs.Count -eq 0) {
			$lines.Add("`t`t`tTerminalTabs  = @()")
		}
		else {
			$lines.Add("`t`t`tTerminalTabs  = @(")
			foreach ($terminalTab in $terminalTabs) {
				$lines.Add("`t`t`t`t@{ WindowHandle = $(& $number $terminalTab.WindowHandle); Title = $(& $quote $terminalTab.Title) }")
			}
			$lines.Add("`t`t`t)")
		}

		$lines.Add("`t`t}")
	}

	$lines.Add("`t)")
	$lines.Add('}')

	return ($lines -join "`n") + "`n"
}
