function Resolve-VSCodeProfilesConfig {
	<#
	.SYNOPSIS
		Resolves the VSCodeProfiles configuration section into expanded paths, the catalogue and this machine type's selection.

	.DESCRIPTION
		Reads `VSCodeProfiles` from the merged configuration and returns one hashtable that
		Deploy-VSCodeProfiles and Export-VSCodeProfile share, so both agree on where profiles
		live in the repository, where VS Code keeps its user data and which profiles this
		machine type deploys:

		  Root          The profile folders in the repository (default {RepoRoot}\VSCode\Profiles),
		                one subfolder per catalogue entry.
		  UserData      VS Code's user data folder (default {AppData}\Code\User). Its root is the
		                Default profile; other profiles live under profiles\<location>.
		  SettingsSync  $true when Settings Sync manages extensions too; $false installs them with
		                --do-not-sync so Sync leaves them alone. Default $false.
		  Prune         $true when extensions the list does not name are uninstalled. Default $false.
		  Entries       Ordered dictionary of catalogue name -> @{ Name; Target; Source }, in
		                catalogue order. Target is the VS Code profile the entry deploys onto
		                (defaults to the entry name); Source is the entry's folder under Root.
		  Selected      The catalogue names Deploy lists for the machine type: its own key when
		                present, otherwise Default, otherwise none.
		  Unknown       Selected names that are not in the catalogue.

		Only the {RepoRoot}, {User} and {AppData} placeholders are expanded - the section is
		machine-type independent apart from Deploy, so it does not go through Expand-ConfigPaths.
		Every key falls back to its default, so the empty base configuration resolves to an
		empty catalogue and an empty selection.

	.PARAMETER Configuration
		The configuration to read (a hashtable or an object, as Get-ConfigSetting accepts).
		Defaults to $global:Configuration.

	.PARAMETER MachineType
		The machine type whose Deploy list is selected. Defaults to $global:MachineType.

	.PARAMETER RepoRoot
		Repository root used for {RepoRoot}. Defaults to Get-RepositoryPath.

	.EXAMPLE
		(Resolve-VSCodeProfilesConfig).Selected
		Returns the catalogue names this machine type deploys, e.g. MyProfile.

	.EXAMPLE
		(Resolve-VSCodeProfilesConfig -MachineType Work).Entries['MyProfile'].Target
		Returns the VS Code profile the MyProfile entry deploys onto, e.g. Default.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[AllowNull()]
		[object]$Configuration = $global:Configuration,

		[Parameter()]
		[string]$MachineType = $global:MachineType,

		[Parameter()]
		[string]$RepoRoot
	)

	if (-not $RepoRoot) {
		$RepoRoot = (Get-RepositoryPath).Repo
	}

	$section = Get-ConfigSetting -Path 'VSCodeProfiles' -Default @{} -Configuration $Configuration
	if ($section -isnot [hashtable]) {
		$section = @{}
	}

	$expand = @{ '{RepoRoot}' = $RepoRoot; '{User}' = $env:USERPROFILE; '{AppData}' = $env:APPDATA }
	$root = if ($section.Root) { [string]$section.Root } else { "{RepoRoot}\VSCode\Profiles" }
	$userData = if ($section.UserData) { [string]$section.UserData } else { "{AppData}\Code\User" }
	foreach ($placeholder in $expand.Keys) {
		$root = $root.Replace($placeholder, $expand[$placeholder])
		$userData = $userData.Replace($placeholder, $expand[$placeholder])
	}

	$entries = [ordered]@{}
	foreach ($name in @(Get-OrderedNames $section.Catalogue)) {
		$entry = Get-OrderedEntry -Section $section.Catalogue -Name $name
		$target = if ($entry -is [hashtable] -and $entry.Target) { [string]$entry.Target } else { $name }
		$entries[$name] = @{
			Name   = $name
			Target = $target
			Source = Join-Path $root $name
		}
	}

	$selected = @()
	if ($section.Deploy -is [hashtable]) {
		if ($MachineType -and $section.Deploy.ContainsKey($MachineType)) {
			$selected = @($section.Deploy[$MachineType])
		}
		elseif ($section.Deploy.ContainsKey('Default')) {
			$selected = @($section.Deploy['Default'])
		}
	}
	$selected = @($selected | ForEach-Object { [string]$_ } | Where-Object { $_ })
	$unknown = @($selected | Where-Object { -not $entries.Contains($_) })

	return @{
		Root         = $root
		UserData     = $userData
		SettingsSync = [bool]$section.SettingsSync
		Prune        = [bool]$section.Prune
		Entries      = $entries
		Selected     = $selected
		Unknown      = $unknown
	}
}
