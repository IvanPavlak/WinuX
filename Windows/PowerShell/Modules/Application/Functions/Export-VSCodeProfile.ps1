function Export-VSCodeProfile {
	<#
	.SYNOPSIS
		Captures a live VS Code profile into its catalogue folder in the repository.

	.DESCRIPTION
		The capture side of Deploy-VSCodeProfiles, run by hand - never by Bootstrap. For the
		VSCodeProfiles.Catalogue entry -Name, the VS Code profile it deploys onto (its Target)
		is located without registering anything (Get-VSCodeProfileLocation), and its folder
		under VSCodeProfiles.Root is created when missing. Then:

		- Every profile file (settings.json, keybindings.json, tasks.json, snippets\; see
		  Get-VSCodeProfileItems) that is a symbolic link already is left alone - it points at
		  the repository, which is the source. A link that points elsewhere is reported.
		- Every real file is copied into the folder, replacing the repository copy. On Windows
		  keybindings land in keybindings.windows.json when the folder carries one,
		  keybindings.json otherwise. An empty snippets folder is not copied.
		- extensions.txt is merged with what the profile has installed
		  (Merge-VSCodeExtensionList): comments, pins and entries still installed are kept,
		  uninstalled entries removed and new extensions appended sorted. VS Code's command
		  line cannot report whether an extension is disabled, so a disabled extension is
		  listed like any other - delete its line to stop deploying it.

		Review the result with `git diff` before committing it. Nothing in VS Code changes.

	.PARAMETER Name
		The catalogue entry to capture.

	.PARAMETER Command
		The VS Code command line to run. Defaults to Get-VSCodeCliPath; tests pass a stub script.

	.EXAMPLE
		Export-VSCodeProfile -Name MyProfile
		Captures the VS Code profile MyProfile deploys onto into VSCode\Profiles\MyProfile.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name,

		[Parameter()]
		[string]$Command
	)

	Write-LogTitle "Exporting VS Code Profile [$Name]"

	$config = Resolve-VSCodeProfilesConfig
	if (-not $config.Entries.Contains($Name)) {
		Write-LogError "VS Code profile [$Name] is not in VSCodeProfiles.Catalogue - add it there first!"
		return
	}
	$entry = $config.Entries[$Name]

	$location = Get-VSCodeProfileLocation -Name $entry.Target -UserData $config.UserData
	if (-not $location -or -not (Test-Path -LiteralPath $location -PathType Container)) {
		Write-LogError "VS Code has no profile [$($entry.Target)] on this machine - nothing to export!"
		return
	}

	Initialize-Directory $entry.Source

	foreach ($item in @(Get-VSCodeProfileItems -Source $entry.Source -Location $location)) {
		if (-not (Test-Path -LiteralPath $item.Live)) { continue }

		$live = Get-Item -LiteralPath $item.Live -Force
		if ($live.LinkType -eq 'SymbolicLink') {
			$linkTarget = [string]@($live.Target)[0]
			if ([System.IO.Path]::GetFullPath($linkTarget) -ne [System.IO.Path]::GetFullPath($item.Repo)) {
				Write-LogWarning "[$($item.Live)] links to [$linkTarget], not to the repository [$($item.Repo)] - left alone!"
			}
			else {
				Write-LogDebug "[$($item.Name)] is linked into the repository already"
			}
			continue
		}

		if ($item.IsDirectory) {
			if (-not (Get-ChildItem -LiteralPath $item.Live -Force | Select-Object -First 1)) { continue }
			Initialize-Directory $item.Repo
			Copy-Item -Path (Join-Path $item.Live "*") -Destination $item.Repo -Recurse -Force
		}
		else {
			Copy-Item -LiteralPath $item.Live -Destination $item.Repo -Force
		}
		Write-LogSuccess "Captured [$($item.Name)] => [$($item.Repo)]"
	}

	if (-not $Command) {
		$Command = Get-VSCodeCliPath
	}
	if (-not $Command) {
		Write-LogWarning "VS Code command line (code) not found - extensions.txt was not updated!"
		return
	}

	$installed = Get-VSCodeInstalledExtensions -Command $Command -ProfileName $entry.Target
	if ($null -eq $installed) {
		Write-LogError "Could not list the extensions of VS Code profile [$($entry.Target)] - extensions.txt was not updated!"
		return
	}

	$listPath = Join-Path $entry.Source "extensions.txt"
	# Plain assignment: `$x = if (...) { @() }` yields $null, which -Lines would bind as one
	# empty line and write as a blank first line.
	$lines = @()
	if (Test-Path -LiteralPath $listPath) { $lines = @(Get-Content -LiteralPath $listPath) }
	$merged = @(Merge-VSCodeExtensionList -Lines $lines -Installed @($installed.Keys))
	Set-Content -LiteralPath $listPath -Value $merged -Encoding utf8NoBOM
	Write-LogSuccess "Captured $($installed.Count) extension(s) => [$listPath]"
}
