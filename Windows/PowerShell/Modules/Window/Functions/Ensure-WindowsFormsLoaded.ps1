function Ensure-WindowsFormsLoaded {
	<#
	.SYNOPSIS
		Ensures the System.Windows.Forms assembly is loaded.

	.DESCRIPTION
		Loads the System.Windows.Forms assembly if not already loaded.
		Uses a module-scoped flag to avoid repeated Add-Type calls.

	.EXAMPLE
		Ensure-WindowsFormsLoaded
	#>
	if (-not $script:WindowsFormsLoaded) {
		Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
		$script:WindowsFormsLoaded = $true
	}
}
