function GitWorktreeRemoveAndPrune {
	<#
	.SYNOPSIS
		Prunes stale worktree entries, removes linked worktrees, and offers to delete their branches.

	.DESCRIPTION
		Runs `git worktree prune` first, so a worktree whose folder was deleted by hand is dropped
		and never offered. Then runs `git worktree remove <path>` on each named worktree, which
		refuses one with uncommitted changes or untracked files; -Force passes `--force` and
		discards them.
		A worktree is named by the branch checked out in it or by its path. The main worktree,
		the one the shell is in and a locked one are never removed (unlock it with
		`git worktree unlock` first). Each worktree is removed on its own, so one that fails
		keeps the others.
		Without -Worktree, the linked worktrees are offered through Resolve-Selection
		(`branch -> path`), which takes one or more; the locked ones are listed apart and
		pressing Enter removes nothing.
		When a removed worktree had a branch, it asks once whether to delete those branches:
		Enter or No keeps them, Yes runs GitBranchDeleteAndPrune (which offers to force the
		unmerged ones), Force runs GitBranchDeleteAndPrune -Force. -Force of this function never
		answers that question.
		Alias: gwd

	.PARAMETER Worktree
		Branch name(s) or path(s) of the worktree(s) to remove. Omit it to pick from a menu.

	.PARAMETER Force
		Removes with `git worktree remove --force`, discarding uncommitted changes and
		untracked files in the worktree.

	.EXAMPLE
		GitWorktreeRemoveAndPrune -Worktree "feature/done"
		Removes the worktree that has "feature/done" checked out, then asks about the branch.

	.EXAMPLE
		gwd ..\MyRepo-hotfix -Force
		Removes the worktree at that path even with uncommitted changes in it.

	.EXAMPLE
		gwd
		Lists the linked worktrees and removes the ones selected; Enter removes none.
	#>
	param(
		[Parameter(Position = 0)]
		[string[]] $Worktree,

		[switch] $Force
	)

	git worktree prune
	if ($LASTEXITCODE -ne 0) {
		return
	}
	$porcelain = @(git worktree list --porcelain)
	if ($LASTEXITCODE -ne 0) {
		return
	}

	# One record per blank-line-separated block; the first block is the main worktree.
	$worktrees = @()
	$entry = $null
	foreach ($line in @($porcelain) + "") {
		if ($line -match '^worktree (.+)$') {
			$entry = [PSCustomObject]@{ Path = $Matches[1]; Head = ""; Branch = $null; Locked = $false; IsMain = ($worktrees.Count -eq 0); IsCurrent = $false; Label = "" }
		}
		elseif (-not $entry) {
			continue
		}
		elseif ($line -match '^HEAD (\S+)') {
			$entry.Head = $Matches[1]
		}
		elseif ($line -match '^branch refs/heads/(.+)$') {
			$entry.Branch = $Matches[1]
		}
		elseif ($line -match '^locked( |$)') {
			$entry.Locked = $true
		}
		elseif ($line -eq "") {
			$worktrees += $entry
			$entry = $null
		}
	}

	# git prints forward slashes on Windows; compare full paths in one spelling, case-insensitively.
	$normalize = { param($path) ([System.IO.Path]::GetFullPath(($path -replace '/', '\'))).TrimEnd('\') }
	$top = git rev-parse --show-toplevel 2>$null
	$currentPath = if ($LASTEXITCODE -eq 0 -and $top) { & $normalize $top } else { $null }
	foreach ($wt in $worktrees) {
		$wt.IsCurrent = ($currentPath -and (& $normalize $wt.Path) -eq $currentPath)
		$name = if ($wt.Branch) { $wt.Branch } else { "(detached $($wt.Head.Substring(0, [Math]::Min(7, $wt.Head.Length))))" }
		$wt.Label = "$name -> $($wt.Path)"
	}

	$targets = @()
	if ($Worktree) {
		foreach ($value in @($Worktree | Where-Object { $_ })) {
			$match = $worktrees | Where-Object { $_.Branch -and $_.Branch -ceq $value } | Select-Object -First 1
			if (-not $match) {
				$candidate = if ([System.IO.Path]::IsPathRooted($value)) { $value } else { Join-Path (Get-Location).ProviderPath $value }
				$candidate = & $normalize $candidate
				$match = $worktrees | Where-Object { (& $normalize $_.Path) -eq $candidate } | Select-Object -First 1
			}

			if (-not $match) {
				Write-Host -ForegroundColor Red "`n=> No worktree has [$value] checked out or lives at that path"
			}
			elseif ($match.IsMain) {
				Write-Host -ForegroundColor Red "`n=> [$value] is the main worktree, which git never removes"
			}
			elseif ($match.IsCurrent) {
				Write-Host -ForegroundColor Red "`n=> [$value] is the worktree you are in - leave it first"
			}
			elseif ($match.Locked) {
				Write-Host -ForegroundColor Red "`n=> [$value] is locked - run git worktree unlock first"
			}
			elseif ($targets -notcontains $match) {
				$targets += $match
			}
		}
	}
	else {
		$locked = @($worktrees | Where-Object { -not $_.IsMain -and -not $_.IsCurrent -and $_.Locked })
		$removable = @($worktrees | Where-Object { -not $_.IsMain -and -not $_.IsCurrent -and -not $_.Locked })

		foreach ($wt in $locked) {
			Write-Host -ForegroundColor Yellow "`n=> [locked] $($wt.Label) - not offered, run git worktree unlock first"
		}
		if ($removable.Count -eq 0) {
			Write-Host -ForegroundColor Yellow "`n=> No worktree to remove besides the main and the current one"
			return
		}

		$labels = @(Resolve-Selection -OptionList @($removable.Label) -MenuTitle "[Worktrees]" `
				-PromptMessage "Enter worktree(s) to remove by number or name, or press [Enter] to remove none" `
				-AllowEmptyPromptResponse -AllowMultipleSelections | Where-Object { $_ })
		$targets = @($removable | Where-Object { $labels -contains $_.Label })
	}

	if ($targets.Count -eq 0) {
		return
	}
	# Keeps the answer apart from git's output below it.
	Write-Host ""

	$branches = @()
	foreach ($wt in $targets) {
		if ($Force) {
			git worktree remove --force $wt.Path
		}
		else {
			git worktree remove $wt.Path
		}
		if ($LASTEXITCODE -eq 0) {
			Write-Host -ForegroundColor Green "=> Removed $($wt.Label)"
			if ($wt.Branch) {
				$branches += $wt.Branch
			}
		}
	}

	if ($branches.Count -eq 0) {
		return
	}
	$answer = Resolve-Selection -OptionList @("Yes", "No", "Force") -DefaultOptionIndex 2 -HideMenuTitle `
		-PromptMessage "Also delete branch(es) $($branches -join ', ')? Force uses git branch -D"
	if ($answer -in "Yes", "Force") {
		# Keeps the answer apart from git's output below it.
		Write-Host ""
	}
	switch ($answer) {
		"Yes" { GitBranchDeleteAndPrune -BranchName $branches }
		"Force" { GitBranchDeleteAndPrune -BranchName $branches -Force }
	}
}
