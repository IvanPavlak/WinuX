function Get-PwshPath {
	<#
	.SYNOPSIS
		Returns a pwsh.exe path that keeps working after PowerShell updates, for the MSI and the MSIX install alike.

	.DESCRIPTION
		The one place that decides which pwsh.exe a scheduled task or another long-lived launcher
		should start. The answer follows the PowerShell that runs this shell:

		1. Installed from the MSI, a zip or anywhere else outside WindowsApps: its own pwsh.exe
		   under $PSHOME. That folder (C:\Program Files\PowerShell\7 for the MSI) does not change
		   when PowerShell is updated.
		2. Installed as the MSIX package (what winget ships from PowerShell 7.7.0): $PSHOME is the
		   versioned package folder (C:\Program Files\WindowsApps\Microsoft.PowerShell_7.7.0.0_x64__8wekyb3d8bbwe),
		   which the next update removes. The function returns the package's own app execution
		   alias instead, %LOCALAPPDATA%\Microsoft\WindowsApps\<PackageFamilyName>\pwsh.exe: it
		   names no version, so it survives updates, and it names the package, so it never starts
		   the PowerShell LTS package (or the MSI) by mistake when several are installed. When that
		   alias is missing, the shared alias %LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe follows.

		When none of these exists, the first pwsh on PATH is returned, and as a last resort the
		pwsh.exe under -PowerShellHome, even if it does not exist.

	.PARAMETER PowerShellHome
		The installation folder to resolve from. Defaults to $PSHOME, the folder of the PowerShell
		that runs this shell.

	.OUTPUTS
		System.String. The full path of pwsh.exe.

	.EXAMPLE
		Get-PwshPath
		C:\Program Files\PowerShell\7\pwsh.exe in a shell of the MSI install;
		C:\Users\<User>\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe
		in a shell of the MSIX install.

	.EXAMPLE
		New-ScheduledTaskAction -Execute (Get-PwshPath) -Argument '-NoProfile -Command ...'
		A scheduled task that still starts after the next PowerShell update.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter()]
		[string]$PowerShellHome = $PSHOME
	)

	$ownPath = Join-Path -Path $PowerShellHome -ChildPath 'pwsh.exe'
	$aliasRoot = Join-Path -Path ([string]$env:LOCALAPPDATA) -ChildPath 'Microsoft\WindowsApps'

	if ($PowerShellHome -notmatch '\\WindowsApps\\') {
		if (Test-Path -LiteralPath $ownPath -PathType Leaf) { return $ownPath }
	}
	else {
		# A package folder is named <Name>_<Version>_<Architecture>_<ResourceId>_<PublisherId>,
		# and its family name, which the alias folder carries, is <Name>_<PublisherId>.
		$packageFolder = Split-Path -Path $PowerShellHome.TrimEnd('\') -Leaf
		if ($packageFolder -match '^(?<Name>[^_]+)_[^_]+_[^_]*_[^_]*_(?<Publisher>[^_]+)$') {
			$familyAlias = Join-Path -Path $aliasRoot -ChildPath "$($Matches.Name)_$($Matches.Publisher)\pwsh.exe"
			if (Test-Path -LiteralPath $familyAlias) { return $familyAlias }
		}

		$sharedAlias = Join-Path -Path $aliasRoot -ChildPath 'pwsh.exe'
		if (Test-Path -LiteralPath $sharedAlias) { return $sharedAlias }
	}

	$onPath = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($onPath) { return [string]$onPath.Source }

	$ownPath
}
