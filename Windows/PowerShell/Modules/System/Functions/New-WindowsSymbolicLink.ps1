function New-WindowsSymbolicLink {
	<#
	.SYNOPSIS
		Creates a single native Windows symbolic link.

	.DESCRIPTION
		Creates a symbolic link at Path pointing to Target. The parent directory is
		created if missing and any pre-existing item at Path is removed first.

		Never links to a missing target - that would delete the real file at Path,
		leave a dangling link, and pointlessly create parent folders; such calls are
		skipped with a warning and self-heal on the next run once the target exists.

		Requires administrator privileges (or Developer Mode).

	.PARAMETER Path
		Where the symbolic link is created.

	.PARAMETER Target
		What the symbolic link points to.

	.PARAMETER DisplayName
		Label used in log messages (SymbolicLinkMaker passes the entry's dotted key,
		e.g. "PowerToys.Settings"). Defaults to Path.

	.EXAMPLE
		New-WindowsSymbolicLink -Path "$env:USERPROFILE\.gitconfig" -Target "C:\Repo\Git\.gitconfig"
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[Parameter(Mandatory)]
		[string]$Target,

		[string]$DisplayName = ""
	)

	if (-not $DisplayName) {
		$DisplayName = $Path
	}

	if (-not (Test-Path $Target)) {
		Write-LogWarning "Skipped symlink (target does not exist) => [$DisplayName] => [$Target]"
		return
	}

	$parentDir = Split-Path -Parent $Path
	if ($parentDir -and -not (Test-Path $parentDir)) {
		Initialize-Directory $parentDir
	}

	if (Test-Path $Path) {
		Remove-Item -Path $Path -Force | Out-Null
		Write-LogWarning "Removed existing item => [$Path]"
	}

	try {
		New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null
		Write-LogSuccess "Created symlink => [$Path] => [$Target]"
	}
	catch {
		Write-LogError "Failed to create symlink for => $DisplayName => $($_.Exception.Message)"
	}
}
