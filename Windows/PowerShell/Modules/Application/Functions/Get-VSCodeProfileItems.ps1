function Get-VSCodeProfileItems {
	<#
	.SYNOPSIS
		Maps the files of a profile folder in the repository onto the files of a VS Code profile.

	.DESCRIPTION
		The one list of what a profile carries, shared by Deploy-VSCodeProfiles (links the
		repository files into the profile) and Export-VSCodeProfile (copies the profile's files
		into the repository). Returns one hashtable per item, in this order:

		  settings.json     -> <profile>\settings.json
		  keybindings.json  -> <profile>\keybindings.json
		  tasks.json        -> <profile>\tasks.json
		  snippets\         -> <profile>\snippets\ (a folder)

		Keybindings are the one per-platform item: on Windows the repository's
		keybindings.windows.json is used when it exists, keybindings.json otherwise, so a
		profile shared with the Mac (keybindings.macos.json) can bind ctrl where the Mac binds
		cmd. extensions.txt is not a file of the profile - the extension commands deploy it -
		so it is not listed.

		Each item is @{ Name; Repo; Live; IsDirectory; InRepo }, where InRepo says whether the
		repository side exists. Nothing is created or read beyond that existence check.

	.PARAMETER Source
		The profile's folder in the repository.

	.PARAMETER Location
		The VS Code profile's folder (Get-VSCodeProfileLocation).

	.EXAMPLE
		Get-VSCodeProfileItems -Source C:\Repo\VSCode\Profiles\MyProfile -Location (Get-VSCodeProfileLocation Default) | Where-Object InRepo
		Returns the items the repository carries for MyProfile.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory)]
		[string]$Source,

		[Parameter(Mandatory)]
		[string]$Location
	)

	$keybindings = "keybindings.json"
	if (Test-Path -LiteralPath (Join-Path $Source "keybindings.windows.json")) {
		$keybindings = "keybindings.windows.json"
	}

	$items = @(
		@{ Name = "settings.json"; Repo = "settings.json"; IsDirectory = $false }
		@{ Name = "keybindings.json"; Repo = $keybindings; IsDirectory = $false }
		@{ Name = "tasks.json"; Repo = "tasks.json"; IsDirectory = $false }
		@{ Name = "snippets"; Repo = "snippets"; IsDirectory = $true }
	)

	foreach ($item in $items) {
		$repo = Join-Path $Source $item.Repo
		@{
			Name        = $item.Name
			Repo        = $repo
			Live        = Join-Path $Location $item.Name
			IsDirectory = $item.IsDirectory
			InRepo      = [bool](Test-Path -LiteralPath $repo)
		}
	}
}
