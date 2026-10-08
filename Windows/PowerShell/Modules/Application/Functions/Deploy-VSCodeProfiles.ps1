function Deploy-VSCodeProfiles {
	<#
	.SYNOPSIS
		Brings VS Code to the profiles the configuration selects for this machine type: links their files and installs their extensions.

	.DESCRIPTION
		VS Code profiles live in the repository as one folder per VSCodeProfiles.Catalogue
		entry under VSCodeProfiles.Root (settings.json, keybindings.json, tasks.json, snippets\
		and extensions.txt; see Get-VSCodeProfileItems). VSCodeProfiles.Deploy names the
		entries each machine type deploys. For every selected entry:

		1. The VS Code profile the entry deploys onto (its Target, the entry name by default)
		   is located through Get-VSCodeProfileLocation -Register: Default is VS Code's user
		   data folder; any other profile is registered in VS Code's profile list when VS Code
		   does not know it yet, which is refused while VS Code is running.
		2. Every file the folder carries is symlinked into the profile through
		   New-WindowsSymbolicLink, which backs up a real file it replaces. A link already
		   pointing at the repository file is left as it is, and a file the folder does not
		   carry is left alone.
		3. Every extension extensions.txt lists that the profile lacks is installed with
		   `code --install-extension <id> --profile <Target>`; a pinned extension
		   (id@version) installed at another version is reinstalled at the pin. With
		   VSCodeProfiles.SettingsSync off (the default) installs carry --do-not-sync, so
		   Settings Sync neither adds nor removes them. Extensions the list does not name are
		   left installed unless -Prune or VSCodeProfiles.Prune is set, which uninstalls them.

		A name in Deploy that is not in the catalogue is an error; an entry whose folder does
		not exist yet is skipped with a warning; a missing VS Code command line skips the
		extensions with a warning (the links are still made). Idempotent: links in place and
		installed extensions are left alone.

		Called by Bootstrap when the opt-in BootstrapConfig.Steps.VSCodeProfiles toggle is
		enabled (OFF by default), after the package managers so VS Code is installed. The base
		configuration has an empty catalogue, so a vanilla run deploys nothing.

	.PARAMETER Name
		Catalogue entries to deploy instead of the machine type's Deploy list.

	.PARAMETER Prune
		Uninstalls extensions the list does not name, as VSCodeProfiles.Prune = $true does.

	.PARAMETER Command
		The VS Code command line to run. Defaults to Get-VSCodeCliPath; tests pass a stub script.

	.EXAMPLE
		Deploy-VSCodeProfiles
		Deploys every profile VSCodeProfiles.Deploy lists for this machine type.

	.EXAMPLE
		Deploy-VSCodeProfiles -Name MyProfile -Prune
		Deploys MyProfile and uninstalls the extensions its list does not name.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string[]]$Name,

		[Parameter()]
		[switch]$Prune,

		[Parameter()]
		[string]$Command
	)

	Write-LogTitle "Deploying VS Code Profiles"

	$config = Resolve-VSCodeProfilesConfig
	$selected = if ($Name) { @($Name) } else { @($config.Selected) }

	if ($selected.Count -eq 0) {
		Write-LogWarning "No VS Code profiles selected for machine type [$global:MachineType] under VSCodeProfiles.Deploy - nothing to deploy!"
		return
	}

	if (-not $Command) {
		$Command = Get-VSCodeCliPath
	}
	$prune = $Prune -or $config.Prune

	foreach ($profileName in $selected) {
		if (-not $config.Entries.Contains($profileName)) {
			Write-LogError "VS Code profile [$profileName] is not in VSCodeProfiles.Catalogue - skipped!"
			continue
		}

		$entry = $config.Entries[$profileName]
		if (-not (Test-Path -LiteralPath $entry.Source -PathType Container)) {
			Write-LogWarning "VS Code profile [$profileName] has no folder yet [$($entry.Source)] - skipped (capture one with Export-VSCodeProfile -Name $profileName)!"
			continue
		}

		Write-LogStep "[$profileName] => VS Code profile [$($entry.Target)]"

		$location = Get-VSCodeProfileLocation -Name $entry.Target -UserData $config.UserData -Register
		if (-not $location) {
			Write-LogError "VS Code profile [$($entry.Target)] could not be located or registered - [$profileName] skipped!"
			continue
		}

		foreach ($item in @(Get-VSCodeProfileItems -Source $entry.Source -Location $location | Where-Object { $_.InRepo })) {
			$live = Get-Item -LiteralPath $item.Live -Force -ErrorAction SilentlyContinue
			if ($live -and $live.LinkType -eq 'SymbolicLink' -and [string]@($live.Target)[0] -eq $item.Repo) {
				Write-LogDebug "[$($item.Live)] already links to [$($item.Repo)]"
				continue
			}
			New-WindowsSymbolicLink -Path $item.Live -Target $item.Repo -DisplayName "VSCodeProfiles.$profileName.$($item.Name)"
		}

		$listPath = Join-Path $entry.Source "extensions.txt"
		if (-not (Test-Path -LiteralPath $listPath)) {
			Write-LogDebug "VS Code profile [$profileName] has no extensions.txt - no extensions to install"
			continue
		}
		if (-not $Command) {
			Write-LogWarning "VS Code command line (code) not found - the extensions of [$profileName] were not installed; install VS Code and run Deploy-VSCodeProfiles again!"
			continue
		}

		$wanted = @(Get-Content -LiteralPath $listPath | ForEach-Object { ConvertFrom-VSCodeExtensionLine -Line $_ } | Where-Object { $_ })
		$installed = Get-VSCodeInstalledExtensions -Command $Command -ProfileName $entry.Target
		if ($null -eq $installed) {
			Write-LogError "Could not list the extensions of VS Code profile [$($entry.Target)] - [$profileName] extensions skipped!"
			continue
		}

		# Plain assignments: `$x = if (...) { @() }` yields $null, which a splat passes to the
		# command line as an empty argument.
		$profileArguments = @()
		if ($entry.Target -ne 'Default') { $profileArguments = @("--profile", $entry.Target) }
		$syncArguments = @()
		if (-not $config.SettingsSync) { $syncArguments = @("--do-not-sync") }

		foreach ($extension in $wanted) {
			$isInstalled = $installed.Contains($extension.Id)
			if ($isInstalled -and (-not $extension.Version -or $installed[$extension.Id] -eq $extension.Version)) {
				Write-LogDebug "Extension [$($extension.Id)] already installed in [$($entry.Target)]"
				continue
			}

			$id = if ($extension.Version) { "$($extension.Id)@$($extension.Version)" } else { $extension.Id }
			$arguments = @("--install-extension", $id) + $profileArguments + $syncArguments
			if ($isInstalled) { $arguments += "--force" }

			try {
				$global:LASTEXITCODE = 0
				& $Command @arguments *> $null
				if ($LASTEXITCODE -eq 0) {
					Write-LogSuccess "Installed extension [$id] in [$($entry.Target)]"
				}
				else {
					Write-LogError "code --install-extension [$id] failed (exit code $LASTEXITCODE) - run it by hand to see why!"
				}
			}
			catch {
				Write-LogError "code --install-extension [$id] threw => $($_.Exception.Message)"
			}
		}

		if (-not $prune) { continue }

		$wantedIds = @($wanted | ForEach-Object { $_.Id })
		foreach ($id in @($installed.Keys)) {
			if ($wantedIds -contains $id) { continue }
			try {
				$global:LASTEXITCODE = 0
				& $Command --uninstall-extension $id @profileArguments *> $null
				if ($LASTEXITCODE -eq 0) {
					Write-LogSuccess "Uninstalled extension [$id] from [$($entry.Target)] (not in extensions.txt)"
				}
				else {
					Write-LogError "code --uninstall-extension [$id] failed (exit code $LASTEXITCODE) - run it by hand to see why!"
				}
			}
			catch {
				Write-LogError "code --uninstall-extension [$id] threw => $($_.Exception.Message)"
			}
		}
	}

	Write-LogSuccess "VS Code profiles deployed!"
}
