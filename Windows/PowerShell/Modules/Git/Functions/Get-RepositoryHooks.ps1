function Get-RepositoryHooks {
	<#
	.SYNOPSIS
		Lists every repository marked with Hooks and the core.hooksPath found in its clone.

	.DESCRIPTION
		The read-only check of the tracked-hooks mechanism (Sync-RepositoryHooks): a clone
		where the setting is missing is seen, not assumed. For every RepositoryGroups entry
		that carries `Hooks = "<folder>"` it reads `git config --local core.hooksPath` of the
		clone and reports one state:

		- Active         the value is the configured folder, and the folder exists
		- NotSet         no value; the next Update-Repositories writes it
		- Different      another value (set by hand); the next Update-Repositories replaces it
		- MissingFolder  the configured folder does not exist in the working tree (a branch
		                 without it, a typo), so no hook runs
		- NotCloned      the repository is not on this machine
		- NotConfigured  the repository has no local path on this machine
		- NotARepository the path is not the top of its own working tree

		A clone the state file still records although its entry is no longer marked is listed
		as Stale: the next Update-Repositories of that repository takes the value back.

		It never writes git configuration or the state file.

	.PARAMETER PassThru
		Return the rows instead of only printing them.

	.OUTPUTS
		With -PassThru, one [pscustomobject] per row: Name, Group, LocalPath, HooksPath (the
		configured folder, $null for a Stale row), Found (the value in the clone, $null when
		unset or not read) and State.

	.EXAMPLE
		Get-RepositoryHooks
		One line per marked repository: green when its hooks are active, yellow otherwise.

	.EXAMPLE
		Get-RepositoryHooks -PassThru | Where-Object State -ne Active
		The marked repositories whose hooks do not run on this machine.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$PassThru
	)

	Write-LogTitle "Repository Hooks"

	$rows = @()
	$markedPaths = @{}
	$targets = Resolve-RepositoryTargets -All

	foreach ($target in $targets) {
		if ([string]::IsNullOrWhiteSpace($target.Hooks)) { continue }

		$folder = "$($target.Hooks)".Trim() -replace '\\', '/'
		if ($folder.Length -gt 1) { $folder = $folder.TrimEnd('/') }
		$found = $null

		if ([string]::IsNullOrWhiteSpace($target.LocalPath)) {
			$state = "NotConfigured"
		}
		elseif (-not (Test-Path -LiteralPath $target.LocalPath)) {
			$state = "NotCloned"
		}
		else {
			$stateKey = try { [IO.Path]::GetFullPath($target.LocalPath).TrimEnd('\', '/') } catch { $target.LocalPath }
			$markedPaths[$stateKey] = $true

			$cdup = git -C $target.LocalPath rev-parse --show-cdup 2>$null
			if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace("$cdup")) {
				$state = "NotARepository"
			}
			else {
				$current = "$(git -C $target.LocalPath config --local --get core.hooksPath 2>$null)".Trim()
				if ($current) { $found = $current }

				$state = if (-not (Test-Path -LiteralPath (Join-Path $target.LocalPath $folder) -PathType Container)) { "MissingFolder" }
				elseif (-not $current) { "NotSet" }
				elseif ($current -ceq $folder) { "Active" }
				else { "Different" }
			}
		}

		$rows += [pscustomobject]@{
			Name      = $target.Name
			Group     = $target.Group
			LocalPath = $target.LocalPath
			HooksPath = $folder
			Found     = $found
			State     = $state
		}
	}

	# What an earlier run wrote for a clone whose entry is no longer marked.
	$recorded = (Get-RepositoryHooksState).Entries
	foreach ($path in @($recorded.Keys | Sort-Object)) {
		if ($markedPaths.ContainsKey($path)) { continue }

		$found = $null
		if (Test-Path -LiteralPath $path) {
			$current = "$(git -C $path config --local --get core.hooksPath 2>$null)".Trim()
			if ($current) { $found = $current }
		}

		$rows += [pscustomobject]@{
			Name      = Split-Path $path -Leaf
			Group     = $null
			LocalPath = $path
			HooksPath = $null
			Found     = $found
			State     = "Stale"
		}
	}

	if ($rows.Count -eq 0) {
		Write-LogStep "=> No repository is marked with Hooks"
	}

	# A blank line sets the first row off from the title; the rest follow without one.
	$noLead = $false
	foreach ($row in $rows) {
		switch ($row.State) {
			"Active" { Write-LogSuccess "[$($row.Name)] core.hooksPath => [$($row.Found)]" -NoLeadingNewline:$noLead }
			"NotSet" { Write-LogWarning "[$($row.Name)] core.hooksPath is not set, [$($row.HooksPath)] is configured - run Update-Repositories" -NoLeadingNewline:$noLead }
			"Different" { Write-LogWarning "[$($row.Name)] core.hooksPath => [$($row.Found)], [$($row.HooksPath)] is configured - run Update-Repositories" -NoLeadingNewline:$noLead }
			"MissingFolder" { Write-LogWarning "[$($row.Name)] hooks folder [$($row.HooksPath)] does not exist in [$($row.LocalPath)]" -NoLeadingNewline:$noLead }
			"NotCloned" { Write-LogWarning "[$($row.Name)] is not cloned on this machine" -NoLeadingNewline:$noLead }
			"NotConfigured" { Write-LogWarning "[$($row.Name)] has no local path on this machine" -NoLeadingNewline:$noLead }
			"NotARepository" { Write-LogWarning "[$($row.LocalPath)] is not the top of a git repository" -NoLeadingNewline:$noLead }
			"Stale" { Write-LogWarning "[$($row.Name)] is no longer marked with Hooks, core.hooksPath => [$($row.Found)] at [$($row.LocalPath)] - run Update-Repositories" -NoLeadingNewline:$noLead }
		}
		$noLead = $true
	}

	if ($PassThru) { return $rows }
}
