function SymbolicLinkMaker {
	<#
	.SYNOPSIS
		Creates symbolic links from Configuration.psd1 for the current machine type.

	.DESCRIPTION
		Reads symbolic link configurations from `SymbolicLinks` in `MachineSpecificPaths`.
		Creates Windows symbolic links for paths containing backslashes, and WSL symlinks
		for paths containing forward slashes.

		Idempotent: if a link already exists pointing to the correct target, it is skipped.
		WSL symlinks are skipped with a warning when no WSL distribution is available
		(WSL setup disabled for the machine type, or WSL not initialized yet).
		Entries whose TARGET does not exist are skipped with a warning: linking to a missing
		target would delete whatever real file lives at Path, leave a dangling link, and
		pointlessly create parent folders. The entry self-heals on the next run once the
		target exists.

		Supports nested configurations (hierarchical hashtables) via recursive processing.
		Requires administrator privileges.

	.EXAMPLE
		SymbolicLinkMaker
		Creates all configured symbolic links for the machine type.
	#>

	Test-AdminPrivileges

	$MachineType = DetermineMachineType

	Write-LogTitle "Creating symbolic links for $MachineType"

	if (-not $MachineSpecificPaths.ContainsKey('SymbolicLinks')) {
		Write-LogError "No SymbolicLinks configuration found for $MachineType"
		return
	}

	# WSL symlinks (forward-slash paths) need a working distribution. Probe once up front: when
	# it is missing (WSL setup disabled for this machine type via BootstrapConfig.WSLSetup, or
	# the post-install reboot has not happened yet), skip WSL entries with a warning instead of
	# erroring on every wsl.exe call.
	$wslAvailable = Test-WSLDistributionInstalled

	$processLinks = {
		param (
			[hashtable]$Configuration,
			[string]$Parent = "",
			[int]$Depth = 0
		)

		foreach ($key in $Configuration.Keys) {
			$item = $Configuration[$key]

			if ($item -is [hashtable] -and $item.ContainsKey("Path") -and $item.ContainsKey("Target")) {
				$path = $item.Path
				$target = $item.Target
				$isWSL = ($path -match '/') -or ($target -match '/')

				if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($target)) {
					Write-LogError "Skipping symbolic link with null/empty path or target!"
					continue
				}

				$indent = "  " * $Depth
				Write-LogStep "$indent[$key]"

				if ($isWSL) {
					if (-not $wslAvailable) {
						Write-LogWarning "Skipped WSL symlink (no WSL distribution available) => $($Parent)$key"
						continue
					}

					# Never link to a missing target - it would remove the real file at Path and
					# leave a dangling link. Skips self-heal on the next run.
					wsl test -e $target
					if ($LASTEXITCODE -ne 0) {
						Write-LogWarning "Skipped symlink (target does not exist) => [$($Parent)$key] => [$target]"
						continue
					}

					$lastSlashIndex = $path.LastIndexOf('/')
					if ($lastSlashIndex -gt 0) {
						$parentDir = $path.Substring(0, $lastSlashIndex)
						wsl test -d $parentDir
						if ($LASTEXITCODE -ne 0) {
							wsl mkdir -p $parentDir
							Write-LogSuccess "Created WSL directory => [$parentDir]"
						}
					}

					wsl test -L $path -o -f $path
					if ($LASTEXITCODE -eq 0) {
						wsl rm -f $path
						if ($LASTEXITCODE -eq 0) {
							Write-LogWarning "Removed existing item => [$path]"
						}
						else {
							Write-LogError "Failed to remove existing item => [$path]"
						}
					}

					try {
						wsl ln -s $target $path
						if ($LASTEXITCODE -eq 0) {
							Write-LogSuccess "Created WSL symlink => [$path] => [$target]"
						}
						else {
							Write-LogError "Failed to create WSL symlink for => $($Parent)$key"
						}
					}
					catch {
						Write-LogError "Failed to create WSL symlink for => $($Parent)$key => $($_.Exception.Message)"
					}
				}
				else {
					# Never link to a missing target - it would remove the real file at Path,
					# leave a dangling link, and pointlessly create parent folders (e.g. a
					# {Dev}\Obsidian folder on machines that never use Obsidian). Skips
					# self-heal on the next run once the target exists.
					if (-not (Test-Path $target)) {
						Write-LogWarning "Skipped symlink (target does not exist) => [$($Parent)$key] => [$target]"
						continue
					}

					$parentDir = Split-Path -Parent $path
					if ($parentDir -and -not (Test-Path $parentDir)) {
						Initialize-Directory $parentDir
					}

					if (Test-Path $path) {
						Remove-Item -Path $path -Force | Out-Null
						Write-LogWarning "Removed existing item => [$path]"
					}

					try {
						New-Item -ItemType SymbolicLink -Path $path -Target $target | Out-Null
						Write-LogSuccess "Created symlink => [$path] => [$target]"
					}
					catch {
						Write-LogError "Failed to create symlink for => $($Parent)$key` => $($_.Exception.Message)"
					}
				}
			}
			elseif ($item -is [hashtable]) {
				$indent = "  " * $Depth
				Write-LogStep "$indent[$key]"

				& $processLinks -Configuration $item -Parent "$($Parent)$key." -Depth ($Depth + 1)
			}
		}
	}

	& $processLinks -Configuration $MachineSpecificPaths.SymbolicLinks
	Write-LogSuccess "Symbolic links created!"
}
