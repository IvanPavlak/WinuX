function Cd-Desktop {
	<#
	.SYNOPSIS
		Navigate to the user's Desktop directory.

	.DESCRIPTION
		Sets the current location to the user's Desktop folder using environment variables.
		Equivalent to `cd ~/Desktop`.

	.EXAMPLE
		Cd-Desktop
		Get-ChildItem  # List files on Desktop
	#>
	Set-Location ([environment]::GetFolderPath('Desktop'))
}
