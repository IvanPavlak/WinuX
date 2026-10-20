function Install-VSCodeLocalExtensions {
	<#
	.SYNOPSIS
		Links the repository's local VS Code extensions into VS Code's extensions folder, so VS Code loads them straight from the repository.

	.DESCRIPTION
		VS Code loads every extension folder it finds under its extensions folder
		(%USERPROFILE%\.vscode\extensions) and registers it on its next scan, so a directory
		link is a complete install: no VSIX, no Marketplace. For every local extension
		(Get-VSCodeLocalExtensions over VSCodeProfiles.Extensions) a symbolic link named
		<publisher>.<name>-<version> is made in Destination, pointing at the extension's
		folder in the repository, through New-WindowsSymbolicLink. Editing a file in the
		repository then changes the live extension on the next "Developer: Reload Window".

		- A link already pointing at the extension's folder is left as it is.
		- A link under an older name of the same extension (the version in package.json was
		  bumped) that points at the same folder is removed, so VS Code never loads it twice.
		  Only symbolic links are removed this way - never a real folder.

		Never uninstall a linked extension through VS Code (`code --uninstall-extension`):
		VS Code deletes the extension's folder, and through the link that is the repository
		copy. Deploy-VSCodeProfiles calls this function first and leaves local extensions
		out of its Marketplace install and its -Prune pass for the same reason.

		Requires administrator privileges or Developer Mode, like every symbolic link.

	.PARAMETER Extension
		The local extensions to link, as Get-VSCodeLocalExtensions returns them. Defaults to
		every extension under VSCodeProfiles.Extensions.

	.PARAMETER Destination
		VS Code's extensions folder. Defaults to %USERPROFILE%\.vscode\extensions.

	.EXAMPLE
		Install-VSCodeLocalExtensions
		Links every local extension under VSCodeProfiles.Extensions into VS Code.

	.EXAMPLE
		Install-VSCodeLocalExtensions -Destination "$env:USERPROFILE\.vscode-insiders\extensions"
		Links them into VS Code Insiders instead.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[AllowEmptyCollection()]
		[hashtable[]]$Extension,

		[Parameter()]
		[string]$Destination = (Join-Path $env:USERPROFILE ".vscode\extensions")
	)

	if (-not $PSBoundParameters.ContainsKey('Extension')) {
		$Extension = @(Get-VSCodeLocalExtensions -Root (Resolve-VSCodeProfilesConfig).Extensions)
	}

	if (@($Extension).Count -eq 0) {
		Write-LogDebug "No local VS Code extensions to link"
		return
	}

	foreach ($item in $Extension) {
		$source = [System.IO.Path]::GetFullPath($item.Source).TrimEnd('\')
		$linkPath = Join-Path $Destination $item.LinkName

		# Links of this extension under any other version name, pointing at the same folder.
		$stale = @(Get-ChildItem -LiteralPath $Destination -Directory -Force -ErrorAction SilentlyContinue |
				Where-Object {
					$_.LinkType -eq 'SymbolicLink' -and
					$_.Name -like "$($item.Id)-*" -and
					$_.Name -ne $item.LinkName -and
					@($_.Target)[0] -and
					[System.IO.Path]::GetFullPath([string]@($_.Target)[0]).TrimEnd('\') -eq $source
				})
		foreach ($link in $stale) {
			# No -Recurse: on a directory link it follows the link and deletes the repository copy.
			Remove-Item -LiteralPath $link.FullName -Force
			Write-LogWarning "Removed the stale link [$($link.Name)] of local extension [$($item.Id)]"
		}

		$live = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
		if ($live -and $live.LinkType -eq 'SymbolicLink' -and @($live.Target)[0] -and
			[System.IO.Path]::GetFullPath([string]@($live.Target)[0]).TrimEnd('\') -eq $source) {
			Write-LogDebug "Local extension [$($item.Id)] already links to [$source]"
			continue
		}

		New-WindowsSymbolicLink -Path $linkPath -Target $source -DisplayName "VSCodeProfiles.Extensions.$($item.Id)"
	}
}
