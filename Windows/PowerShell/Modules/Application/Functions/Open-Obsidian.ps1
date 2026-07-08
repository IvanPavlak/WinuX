function Open-Obsidian {
	<#
	.SYNOPSIS
		Opens Obsidian by launching the vault startup Python script.

	.DESCRIPTION
		Starts the Obsidian vault by running `ObsidianStartupScript.pyw` via `pythonw`.
		The script path is resolved from `$MachineSpecificPaths.ObsidianStartupScript`.
		Does nothing if Obsidian is already running.

	.EXAMPLE
		Open-Obsidian
		Opens Obsidian.
	#>
	Start-Application `
		-AppName "Obsidian" `
		-ProcessName "obsidian" `
		-StartMethod DirectPath `
		-ExecutablePath "pythonw" `
		-Arguments $MachineSpecificPaths.ObsidianStartupScript `
		-SkipPathValidation
}
