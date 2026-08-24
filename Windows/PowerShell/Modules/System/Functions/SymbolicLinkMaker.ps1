function SymbolicLinkMaker {
	<#
	.SYNOPSIS
		Creates symbolic links from Configuration.psd1 for the current machine type.

	.DESCRIPTION
		Reads symbolic link configurations from `SymbolicLinks` in `MachineSpecificPaths`,
		flattened and filtered by Get-SymbolicLinkEntries, then creates each link:
		Windows symbolic links (backslash paths) via New-WindowsSymbolicLink and WSL
		symlinks (forward-slash paths) via New-WSLSymbolicLink.

		Modular: -Scope limits the run to Windows-only or WSL-only entries, and -Name
		limits it to specific entries by key (wildcards supported), so one relink never
		has to redo every link.

		WSL symlinks are skipped with a warning when no WSL distribution is available
		(WSL setup disabled for the machine type, or WSL not initialized yet).
		Entries whose TARGET does not exist are skipped with a warning: linking to a
		missing target would delete whatever real file lives at Path, leave a dangling
		link, and pointlessly create parent folders. The entry self-heals on the next
		run once the target exists.

		A real file or directory already sitting at an entry's Path is copied into
		<Repo>\Backups\SymbolicLinks\<entry key>\<timestamp>\ before the link replaces
		it (gitignored, never committed), so a first run over a machine that already has
		its own PowerShell profile or PowerToys settings loses nothing. An entry whose
		backup cannot be written is skipped instead of replaced.

		Requires administrator privileges.

	.PARAMETER Scope
		Which link flavor to process: All (default), Windows (backslash paths only),
		or WSL (forward-slash paths only).

	.PARAMETER Name
		One or more entry keys to process, matched with wildcards against both the bare
		key and the full dotted path (e.g. "PowerToys", "PowerToys.Settings", "WSL*").
		Matching a group processes everything beneath it. Omit to process all entries.

	.EXAMPLE
		SymbolicLinkMaker
		Creates all configured symbolic links for the machine type.

	.EXAMPLE
		SymbolicLinkMaker -Scope WSL
		Recreates only the WSL symlinks (e.g. after a distro reinstall).

	.EXAMPLE
		SymbolicLinkMaker -Name PowerToys
		Recreates only the PowerToys link group.

	.EXAMPLE
		SymbolicLinkMaker -Name "WindowsTerminal.Settings", "FastFetch*"
		Recreates one nested entry and every group matching a wildcard.
	#>
	param(
		[ValidateSet("All", "Windows", "WSL")]
		[string]$Scope = "All",

		[string[]]$Name
	)

	Test-AdminPrivileges

	$MachineType = DetermineMachineType

	Write-LogTitle "Creating symbolic links for $MachineType"

	if (-not (Confirm-ConfigValue $MachineSpecificPaths.SymbolicLinks "SymbolicLinks not configured - nothing to link!")) {
		return
	}

	$entries = @(Get-SymbolicLinkEntries -SymbolicLinks $MachineSpecificPaths.SymbolicLinks -Scope $Scope -Name $Name)
	if ($entries.Count -eq 0) {
		Write-LogWarning "No symbolic link entries match the requested filters - nothing to link!"
		return
	}

	# WSL symlinks need a working distribution. Probe once up front - and only when the
	# selection actually contains WSL entries - so a missing distribution (WSL setup
	# disabled for this machine type via BootstrapConfig.Steps.WSL, or the post-install
	# reboot has not happened yet) skips them with a warning instead of erroring on
	# every wsl.exe call, and a Windows-only run never touches wsl.exe at all.
	$wslAvailable = (@($entries | Where-Object IsWSL).Count -gt 0) -and (Test-WSLDistributionInstalled)
	$wslDistro = $Configuration.DefaultWSLDistribution

	# Entries arrive depth-first, so a group's entries are contiguous: print each
	# ancestor header exactly once, when it differs from the previous entry's chain.
	$previousGroups = @()
	foreach ($entry in $entries) {
		if ([string]::IsNullOrWhiteSpace($entry.Path) -or [string]::IsNullOrWhiteSpace($entry.Target)) {
			Write-LogError "Skipping symbolic link with null/empty path or target!"
			continue
		}

		$segments = $entry.FullKey -split '\.'
		# Plain assignment, NOT `$groups = if (...) {...}`: assigning statement output
		# enumerates it, collapsing a one-element array to a bare string whose [0] is
		# then a single character ("[W]" instead of "[WSLFastFetch]").
		$groups = @()
		if ($segments.Count -gt 1) {
			$groups = @($segments[0..($segments.Count - 2)])
		}
		for ($i = 0; $i -lt $groups.Count; $i++) {
			if ($i -ge $previousGroups.Count -or $previousGroups[$i] -ne $groups[$i]) {
				Write-LogStep ("  " * $i + "[$($groups[$i])]")
			}
		}
		$previousGroups = $groups
		Write-LogStep ("  " * $groups.Count + "[$($entry.Key)]")

		if ($entry.IsWSL) {
			if (-not $wslAvailable) {
				Write-LogWarning "Skipped WSL symlink (no WSL distribution available) => $($entry.FullKey)"
				continue
			}

			New-WSLSymbolicLink -Path $entry.Path -Target $entry.Target -Distribution $wslDistro -DisplayName $entry.FullKey
		}
		else {
			New-WindowsSymbolicLink -Path $entry.Path -Target $entry.Target -DisplayName $entry.FullKey
		}
	}

	Write-LogSuccess "Symbolic links created!"
}
