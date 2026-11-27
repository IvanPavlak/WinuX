function Sync-Win11DebloatSettings {
	<#
	.SYNOPSIS
		Links Win11Debloat's saved settings to the repository file and adopts settings saved outside it.

	.DESCRIPTION
		The vendored Win11Debloat release keeps its saved settings in its user data folder,
		`%LOCALAPPDATA%\Win11Debloat\LastUsedSettings.json`. To keep them version-controlled while
		Win11Debloat reads and writes them natively, that path is made a symbolic link to the
		repository's `Windows\Win11Debloat\LastUsedSettings.json`.

		A real file found at that path was saved by a run that had no link to write through:

		- When the repository file is missing or blank, the saved file is copied into the
		  repository, so a first interactive run starts the tracked settings.
		- When the repository file has settings, it stays the source of truth and the saved file
		  is kept beside the link as `LastUsedSettings.unlinked.<timestamp>.json`, named in a
		  warning. Each one gets its own name, so an earlier one is never overwritten.

		No link is made while the repository file is missing or blank: Win11Debloat deletes a blank
		settings file on start, which would remove the link again.

		Creating the link needs administrator privileges or Developer Mode; a link that cannot be
		created is a terminating error, never a reported success. Start-Win11Debloat calls this
		before its menu and again after an interactive run.

	.OUTPUTS
		[bool] $true when the repository file holds settings (and is linked), otherwise $false.

	.EXAMPLE
		Sync-Win11DebloatSettings
		Links the saved settings, adopting or setting aside a file saved outside the repository.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param()

	$repoRoot = $global:MachineSpecificPaths.Projects.Self.Root
	$repositorySettingsPath = Join-Path $repoRoot "Windows\Win11Debloat\LastUsedSettings.json"
	$userDataPath = Join-Path $env:LOCALAPPDATA "Win11Debloat"
	$userSettingsPath = Join-Path $userDataPath "LastUsedSettings.json"

	$repositoryHasSettings = $false
	if (Test-Path -LiteralPath $repositorySettingsPath) {
		$repositoryContent = Get-Content -LiteralPath $repositorySettingsPath -Raw -ErrorAction SilentlyContinue
		$repositoryHasSettings = -not [string]::IsNullOrWhiteSpace($repositoryContent)
	}

	$userItem = Get-Item -LiteralPath $userSettingsPath -Force -ErrorAction SilentlyContinue
	$userTarget = if ($userItem -and $userItem.Target) { @($userItem.Target)[0] } else { $null }
	$isUserItemLink = $userItem -and $userItem.LinkType -eq 'SymbolicLink'

	if ($isUserItemLink -and $userTarget -eq $repositorySettingsPath) {
		return $repositoryHasSettings
	}

	if ($userItem -and -not $isUserItemLink) {
		$userContent = Get-Content -LiteralPath $userSettingsPath -Raw -ErrorAction SilentlyContinue

		if (-not [string]::IsNullOrWhiteSpace($userContent)) {
			if ($repositoryHasSettings) {
				# Stamped and moved without -Force, so an earlier set-aside file is never overwritten;
				# a failed move stops here instead of falling through to the removal below.
				$unlinkedSettingsPath = Join-Path $userDataPath "LastUsedSettings.unlinked.$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
				Move-Item -LiteralPath $userSettingsPath -Destination $unlinkedSettingsPath -ErrorAction Stop
				Write-LogWarning "Win11Debloat settings saved outside the repo were kept at: $unlinkedSettingsPath"
			}
			else {
				$repositorySettingsDirectory = Split-Path -Path $repositorySettingsPath -Parent
				if (-not (Test-Path -LiteralPath $repositorySettingsDirectory)) {
					New-Item -ItemType Directory -Path $repositorySettingsDirectory -Force | Out-Null
				}

				Copy-Item -LiteralPath $userSettingsPath -Destination $repositorySettingsPath -Force
				$repositoryHasSettings = $true
				Write-LogSuccess "Adopted the saved Win11Debloat settings into the repo's LastUsedSettings.json"
			}
		}
	}

	if (-not $repositoryHasSettings) {
		return $false
	}

	if (-not (Test-Path -LiteralPath $userDataPath)) {
		New-Item -ItemType Directory -Path $userDataPath -Force | Out-Null
	}

	if (Test-Path -LiteralPath $userSettingsPath) {
		Remove-Item -LiteralPath $userSettingsPath -Force
	}

	New-Item -ItemType SymbolicLink -Path $userSettingsPath -Target $repositorySettingsPath -Force -ErrorAction Stop | Out-Null
	Write-LogSuccess "Linked Win11Debloat saved settings to the repo's LastUsedSettings.json"

	return $true
}
