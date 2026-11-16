function Sync-RepositoryHooks {
	<#
	.SYNOPSIS
		Turns one clone's tracked git hooks on or off, to match what the configuration says.

	.DESCRIPTION
		Git does not share hooks through a clone: a repository can track them in a folder (by
		convention `.githooks`), but they run only once `core.hooksPath` names that folder in
		the clone's own git configuration. This is the per-repository step that writes it, for
		a repository whose RepositoryGroups entry carries `Hooks = "<folder>"`, and takes it
		back when the entry no longer does. Update-Repositories calls it for every repository
		it clones or updates, Initialize-Repository for a clone of a marked URL.

		A hook is code the repository runs on this machine at every commit, so nothing is ever
		turned on for a repository the configuration does not mark, whatever folders it holds.

		With -HooksPath (the repository is marked):

		1. A folder that is absolute, starts with `~` or has a `..` segment is refused: the
		   hooks folder is a folder inside the repository.
		2. A folder that does not exist in the working tree (a branch without it, a typo) is
		   reported and nothing is written. It is never created.
		3. `git config --local core.hooksPath` is read and written only when it differs. Only
		   the clone's local configuration is touched: never the global or system level, never
		   `.git/hooks`.
		4. What was written is recorded (Get-RepositoryHooksState), so it can be taken back.

		Without -HooksPath (the repository is not marked):

		1. Nothing recorded for this clone: nothing is read or written, and no git runs.
		2. Recorded, and the value is still the one recorded: it is unset and forgotten.
		3. Recorded, but the value is another one now (set by hand since): it is left alone,
		   reported once, and the record is dropped - it is no longer this function's value.

		A value somebody set by hand to the configured folder is kept as it is and not
		recorded, so it survives the mark being removed.

		A path that is not the top of its own working tree is refused, as Update-Repository
		does: git would otherwise write into whichever repository encloses it.

	.PARAMETER Name
		The repository's display name, used in messages and returned in the result.

	.PARAMETER LocalPath
		The repository's working-tree path.

	.PARAMETER HooksPath
		The hooks folder, relative to the repository root (".githooks"). Empty or absent means
		the repository is not marked.

	.PARAMETER Quiet
		Log nothing; the caller reports the returned result.

	.OUTPUTS
		[pscustomobject] with Name, LocalPath, HooksPath (the configured folder, normalized),
		Found (core.hooksPath after the call, $null when unset or not read) and Outcome:
		None (not marked, nothing recorded), Set, AlreadySet, MissingFolder, Invalid, Removed,
		Kept (not marked any more, but the value was changed by hand and is left alone),
		NotARepository, or Error (git refused the write).

	.EXAMPLE
		Sync-RepositoryHooks -Name MyRepo -LocalPath "C:\Dev\MyRepo" -HooksPath ".githooks"
		Points core.hooksPath of that clone at .githooks, unless it already does.

	.EXAMPLE
		Sync-RepositoryHooks -Name MyRepo -LocalPath "C:\Dev\MyRepo"
		Takes core.hooksPath back when an earlier call wrote it and it was not changed since.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[string]$LocalPath,

		[Parameter(Mandatory = $false)]
		[string]$HooksPath,

		[Parameter(Mandatory = $false)]
		[switch]$Quiet
	)

	# Either slash is accepted in the configuration; git takes forward slashes on every system.
	$folder = "$HooksPath".Trim() -replace '\\', '/'
	if ($folder.Length -gt 1) { $folder = $folder.TrimEnd('/') }
	$marked = -not [string]::IsNullOrWhiteSpace($folder)

	$result = [pscustomobject]@{
		Name      = $Name
		LocalPath = $LocalPath
		HooksPath = if ($marked) { $folder } else { $null }
		Found     = $null
		Outcome   = "None"
	}

	$state = Get-RepositoryHooksState
	$stateKey = try { [IO.Path]::GetFullPath($LocalPath).TrimEnd('\', '/') } catch { $LocalPath }
	$recorded = $state.Entries[$stateKey]

	# Not marked and never written here: the common case, and it costs no git process.
	if (-not $marked -and -not $recorded) { return $result }

	# The path must be the top of its own working tree, or git would write into the
	# configuration of whichever repository encloses it.
	$cdup = git -C $LocalPath rev-parse --show-cdup 2>$null
	if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace("$cdup")) {
		$result.Outcome = "NotARepository"
		if (-not $Quiet) { Write-LogWarning "[$LocalPath] is not the top of a git repository - its hooks path was not touched" }
		return $result
	}

	$current = "$(git -C $LocalPath config --local --get core.hooksPath 2>$null)".Trim()
	if ($current) { $result.Found = $current }
	$stateChanged = $false

	if ($marked) {
		$segments = $folder -split '/'
		if ([IO.Path]::IsPathRooted($folder) -or $folder.StartsWith('~') -or $segments -contains '..') {
			$result.Outcome = "Invalid"
			if (-not $Quiet) { Write-LogWarning "Hooks folder [$folder] of [$Name] is not a folder inside the repository - core.hooksPath was not written" }
		}
		elseif (-not (Test-Path -LiteralPath (Join-Path $LocalPath $folder) -PathType Container)) {
			$result.Outcome = "MissingFolder"
			if (-not $Quiet) { Write-LogWarning "Hooks folder [$folder] of [$Name] does not exist in [$LocalPath] - core.hooksPath was not written" }
		}
		elseif ($current -ceq $folder) {
			$result.Outcome = "AlreadySet"
		}
		else {
			git -C $LocalPath config --local core.hooksPath $folder 2>$null | Out-Null
			if ($LASTEXITCODE -ne 0) {
				$result.Outcome = "Error"
				if (-not $Quiet) { Write-LogError "Could not write core.hooksPath of [$Name]" }
			}
			else {
				$result.Outcome = "Set"
				$result.Found = $folder
				$state.Entries[$stateKey] = $folder
				$stateChanged = $true
				if (-not $Quiet) {
					$was = if ($current) { " (was [$current])" } else { "" }
					Write-LogSuccess "Hooks path of [$Name] set => [$folder]$was"
				}
			}
		}
	}
	elseif (-not $current -or $current -ceq $recorded) {
		# No longer marked, and the value is still this function's own (or already gone).
		$unsetFailed = $false
		if ($current) {
			git -C $LocalPath config --local --unset core.hooksPath 2>$null | Out-Null
			$unsetFailed = ($LASTEXITCODE -ne 0)
		}
		if ($unsetFailed) {
			$result.Outcome = "Error"
			if (-not $Quiet) { Write-LogError "Could not remove core.hooksPath of [$Name]" }
		}
		else {
			$result.Outcome = "Removed"
			$result.Found = $null
			$state.Entries.Remove($stateKey)
			$stateChanged = $true
			if (-not $Quiet) { Write-LogSuccess "Hooks path of [$Name] removed - the repository is no longer marked with Hooks" }
		}
	}
	else {
		# Changed by hand since it was written: not this function's value any more.
		$result.Outcome = "Kept"
		$state.Entries.Remove($stateKey)
		$stateChanged = $true
		if (-not $Quiet) { Write-LogWarning "[$Name] is no longer marked with Hooks, but its core.hooksPath is [$current], not the [$recorded] written here - left alone" }
	}

	# The state file is rewritten only when what it records changed.
	if ($stateChanged) {
		try {
			New-Item -ItemType Directory -Path (Split-Path -Parent $state.Path) -Force | Out-Null
			$stateText = "# Written by Sync-RepositoryHooks: the core.hooksPath it set, per clone (path<TAB>folder). Do not edit.`n"
			foreach ($key in @($state.Entries.Keys | Sort-Object)) { $stateText += "$key`t$($state.Entries[$key])`n" }
			[IO.File]::WriteAllText($state.Path, $stateText, [Text.UTF8Encoding]::new($false))
		}
		catch {
			Write-LogError "The repository hooks state file [$($state.Path)] was not written => $($_.Exception.Message)" -Exception $_
		}
	}

	return $result
}
