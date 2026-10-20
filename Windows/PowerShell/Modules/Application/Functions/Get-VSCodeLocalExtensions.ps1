function Get-VSCodeLocalExtensions {
	<#
	.SYNOPSIS
		Lists the unpackaged VS Code extensions kept in the repository, read from their package.json.

	.DESCRIPTION
		A local extension is a folder under Root that holds a package.json - a complete VS Code
		extension that is never packaged or published, such as a colour theme of your own. For
		each one the manifest's publisher, name and version give:

		  Id        <publisher>.<name>, lowercased - the id VS Code lists it under.
		  Version   The manifest version.
		  LinkName  <Id>-<Version>, the folder name VS Code expects under its extensions folder.
		  Source    The extension's folder in the repository.

		Folders without a package.json are ignored. A package.json that is not valid JSON, or
		that lacks publisher, name or version, is skipped with a warning. A missing Root lists
		nothing. The result is sorted by folder name and emitted one by one (wrap the call in
		@(...) for an array). Nothing is changed.

	.PARAMETER Root
		The folder holding one subfolder per local extension (VSCodeProfiles.Extensions).

	.EXAMPLE
		Get-VSCodeLocalExtensions -Root "C:\Repo\VSCode\Extensions"
		Lists every local extension, e.g. @{ Id = "publisher.themes"; Version = "1.0.0"; ... }.
	#>
	[CmdletBinding()]
	[OutputType([hashtable[]])]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Root
	)

	if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
		Write-LogDebug "No local VS Code extensions folder [$Root]"
		return @()
	}

	$extensions = [System.Collections.Generic.List[hashtable]]::new()
	foreach ($folder in @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name)) {
		$manifestPath = Join-Path $folder.FullName "package.json"
		if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }

		try {
			$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
		}
		catch {
			Write-LogWarning "[$manifestPath] is not valid JSON - local extension [$($folder.Name)] skipped!"
			continue
		}

		$publisher = [string]$manifest.publisher
		$name = [string]$manifest.name
		$version = [string]$manifest.version
		if (-not $publisher -or -not $name -or -not $version) {
			Write-LogWarning "[$manifestPath] needs publisher, name and version - local extension [$($folder.Name)] skipped!"
			continue
		}

		$id = "$publisher.$name".ToLowerInvariant()
		$extensions.Add(@{
				Id       = $id
				Version  = $version
				LinkName = "$id-$version"
				Source   = $folder.FullName
			})
	}

	return $extensions.ToArray()
}
