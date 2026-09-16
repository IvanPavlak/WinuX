function Enable-ObsidianCli {
	<#
	.SYNOPSIS
		Turns on the Obsidian command line interface for this machine.

	.DESCRIPTION
		The CLI toggle (Settings > General > Advanced > Command line interface) is Obsidian
		application state, not vault state: Obsidian keeps it as `"cli": true` in
		%APPDATA%\obsidian\obsidian.json, the same file that lists the known vaults. A synced
		.obsidian folder therefore never carries it from one machine to the next, and Open-Obsidian
		cannot load a workspace until it is set. This function sets it.

		Obsidian rewrites obsidian.json on every settings change, so the flag is only written while
		Obsidian is not running; with Obsidian up the function says so and does nothing. A missing
		obsidian.json means Obsidian has never been started on this machine - start it once first,
		the file is not invented. No PATH step is needed: Get-ObsidianCliPath finds Obsidian.com
		beside Obsidian.exe, and AutoPathAdditions can add the folder for calling `obsidian` by hand.

	.PARAMETER SettingsPath
		The obsidian.json to edit. Defaults to %APPDATA%\obsidian\obsidian.json.

	.EXAMPLE
		Enable-ObsidianCli
		Sets "cli": true in obsidian.json while Obsidian is closed.

	.EXAMPLE
		Enable-ObsidianCli -WhatIf
		Reports what would be written without touching the file.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter()]
		[string]$SettingsPath = (Join-Path $env:APPDATA 'obsidian\obsidian.json')
	)

	if (-not (Test-Path -LiteralPath $SettingsPath)) {
		Write-LogWarning "Obsidian settings file not found at [$SettingsPath] - start Obsidian once on this machine first, it creates the file!"
		return
	}

	if (Get-Process -Name 'obsidian' -ErrorAction SilentlyContinue) {
		Write-LogWarning "Obsidian is running - close it first! Obsidian rewrites [$SettingsPath] on every settings change and would discard the flag."
		return
	}

	try {
		$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
	}
	catch {
		Write-LogError "Error: Could not parse [$SettingsPath] => $($_.Exception.Message)"
		return
	}

	if ($settings.cli -eq $true) {
		Write-LogSuccess "Obsidian CLI is already enabled!"
		return
	}

	$settings | Add-Member -MemberType NoteProperty -Name 'cli' -Value $true -Force

	if ($PSCmdlet.ShouldProcess($SettingsPath, 'Set "cli": true')) {
		# Obsidian writes the file as a single compact line; keep that shape.
		Set-Content -LiteralPath $SettingsPath -Value ($settings | ConvertTo-Json -Depth 10 -Compress) -NoNewline -Encoding utf8
		Write-LogSuccess "Obsidian CLI enabled! Start Obsidian, then [Open-Obsidian -Workspace <Name>] can load workspaces."
	}
}
