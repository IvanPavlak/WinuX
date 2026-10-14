function Cd-Desktop {
	<#
	.SYNOPSIS
		Navigate to the user's Desktop directory.

	.DESCRIPTION
		Sets the current location to the user's Desktop folder as resolved by
		[Environment]::GetFolderPath('Desktop'), so a redirected Desktop (e.g. OneDrive) is
		honored. Usually equivalent to `cd ~/Desktop`.

	.EXAMPLE
		Cd-Desktop
		Get-ChildItem  # List files on Desktop
	#>
	Set-Location ([environment]::GetFolderPath('Desktop'))
}
