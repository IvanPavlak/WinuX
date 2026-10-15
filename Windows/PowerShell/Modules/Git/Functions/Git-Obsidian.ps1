Function Git-Obsidian {
	<#
	.SYNOPSIS
		Commits and pushes all pending changes in the Obsidian vault repository.

	.DESCRIPTION
		Navigates to the Obsidian vault directory (`$MachineSpecificPaths.ObsidianDirectory`)
		and brings the remote up to date with the vault:
		- If the working tree has changes, stages everything with `git add .` and creates a
		  commit with message `"Vault Backup: dd.MM.yyyy | HH:mm"`.
		- Counts the commits the current branch has that its upstream does not
		  (`git rev-list --count @{upstream}..HEAD`). That count includes the commit just made
		  and any commit an earlier run left behind when its push failed (no network, remote
		  unreachable). If it is zero, reports that nothing changed and stops.
		- Otherwise pushes, and reports success only when `git push` actually exited 0.

		A failed commit or push is logged as an error, never as "Obsidian updated!", and the
		function says what state the vault is left in. Because the decision to push is made
		from the unpushed-commit count rather than from the working tree alone, the next run
		after a failed push finishes the job instead of reporting "No changes to update!"
		over a clean tree whose last commit never reached the remote.

		Where the shell ends up afterwards is `$Configuration.Obsidian.GitEndLocation`:
		"Current" (the default, also used for an empty or unknown value) returns to the folder
		the function was called from, "Vault" stays in the vault directory.

		An empty ObsidianDirectory is reported as not configured and nothing runs, so git is
		never pointed at whatever folder the shell happens to be in.

	.EXAMPLE
		Git-Obsidian
		Commits and pushes any vault changes, pushes commits an earlier failed run left
		behind, or reports that nothing changed, then returns to the calling folder.
	#>

	Write-LogTitle "Git-Obsidian" -BlankLineAfter

	$vaultDirectory = if ($global:MachineSpecificPaths) { [string]$global:MachineSpecificPaths.ObsidianDirectory } else { '' }
	if ([string]::IsNullOrWhiteSpace($vaultDirectory)) {
		Write-LogWarning "ObsidianDirectory is not configured - set PathTemplates.ObsidianDirectory in Configuration.local.psd1." -NoLeadingNewline
		return
	}

	$endLocation = [string](Get-ConfigSetting -Path 'Obsidian.GitEndLocation' -Default 'Current')
	$startDirectory = (Get-Location).Path

	Set-Location -Path $vaultDirectory

	try {
		$changes = git status --porcelain
		if ($changes) {
			git add .
			$timestamp = Get-Date -Format "dd.MM.yyyy | HH:mm"
			git commit -m "Vault Backup: $timestamp"
			if ($LASTEXITCODE -ne 0) {
				Write-LogError "Commit failed - nothing was pushed!"
				Write-LogWarning "The changes are still in the working tree. Fix the cause and run Git-Obsidian again." -NoLeadingNewline
				return
			}
		}

		# Decide whether to push from what the remote is missing, not from the working tree:
		# a clean tree says nothing about whether the last commit ever left this machine.
		# rev-list fails when the branch has no upstream; treat that as "unknown" and let
		# git push report the real problem rather than hiding it behind "No changes".
		$unpushed = git rev-list --count '@{upstream}..HEAD' 2>$null
		if ($LASTEXITCODE -ne 0) {
			$unpushed = $null
		}

		if (-not $changes -and $unpushed -eq 0) {
			Write-LogWarning "No changes to update!" -NoLeadingNewline
			return
		}

		if (-not $changes) {
			if ($null -eq $unpushed) {
				Write-LogWarning "Could not compare the branch with its upstream. Pushing so git reports the cause..." -NoLeadingNewline -BlankLineAfter
			}
			else {
				Write-LogWarning "Found [$unpushed] unpushed commit(s) from an earlier run. Pushing..." -NoLeadingNewline -BlankLineAfter
			}
		}

		git push
		if ($LASTEXITCODE -ne 0) {
			Write-LogError "Push failed - the vault is committed locally but the remote was not updated!"
			Write-LogWarning "Run Git-Obsidian again once the remote is reachable; it will push the pending commit(s)." -NoLeadingNewline
			return
		}

		Write-LogSuccess "Obsidian updated!"
	}
	catch {
		Write-LogError "Error updating Obsidian!"
		Write-LogError $_.Exception.Message -NoLeadingNewline
	}
	finally {
		# "Vault" leaves the shell where the git commands ran; anything else returns to the caller's folder.
		if ($endLocation -ne 'Vault') {
			Set-Location -Path $startDirectory
		}
	}
}
