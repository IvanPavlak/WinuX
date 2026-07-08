function List-Drives {
	<#
	.SYNOPSIS
		Lists all FileSystem PSDrives (mounted drives).

	.DESCRIPTION
		Alias for `Get-PSDrive -PSProvider FileSystem`. Shows all mounted drives including
		local disks, network drives, and removable media.

	.EXAMPLE
		List-Drives
		Lists all FileSystem drives.
	#>
	& Get-PSDrive -PSProvider 'FileSystem'
}
