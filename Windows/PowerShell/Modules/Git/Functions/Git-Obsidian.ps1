function Git-Obsidian {
	<#
	.SYNOPSIS
		Commits and pushes all pending changes in the Obsidian vault repository.

	.DESCRIPTION
		Navigates to the Obsidian vault directory (`$MachineSpecificPaths.ObsidianDirectory`),
		checks for uncommitted changes, and if any are present:
		- Stages everything with `git add .`
		- Creates a commit with message `"Vault Backup: dd.MM.yyyy | HH:mm"`
		- Pushes to the remote

		Does nothing if there are no changes. Restores the original working directory on exit.

	.EXAMPLE
		Git-Obsidian
		Commits and pushes any vault changes, or reports that nothing changed.
	#>

	Write-LogTitle "Git-Obsidian"

	Set-Location -Path $MachineSpecificPaths.ObsidianDirectory

	try {
		$changes = git status --porcelain
		if ($changes) {
			git add .
			$timestamp = Get-Date -Format "dd.MM.yyyy | HH:mm"
			git commit -m "Vault Backup: $timestamp"
			git push
			Write-LogSuccess "Obsidian updated!"
		}
		else {
			Write-LogWarning "No changes to update!"
		}
	}
	catch {
		Write-LogError "Error updating Obsidian!"
		Write-LogError $_.Exception.Message -NoLeadingNewline
	}
	finally {
		Set-Location -Path $currentDirectory
	}
}
