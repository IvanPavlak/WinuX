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
		obsidian.json means Obsidian has never been started on this machine: by default the function
		says so and writes nothing; with -CreateIfMissing (what the Bootstrap step passes) it writes a
		minimal {"cli":true}, which Obsidian merges with its own defaults on first start and extends
		with the vault list as vaults are opened. No PATH step is needed: Get-ObsidianCliPath finds
		Obsidian.com beside Obsidian.exe, and AutoPathAdditions can add the folder for calling
		`obsidian` by hand.

		Bootstrap runs this as the opt-in step BootstrapConfig.Steps.ObsidianCli (OFF in the base
		configuration, like every step that acts the moment it runs).

	.PARAMETER SettingsPath
		The obsidian.json to edit. Defaults to %APPDATA%\obsidian\obsidian.json.

	.PARAMETER CreateIfMissing
		Write a minimal obsidian.json containing only the flag when the file does not exist yet,
		instead of warning. Bootstrap passes this so a fresh machine is ready before Obsidian's
		first start.

	.EXAMPLE
		Enable-ObsidianCli
		Sets "cli": true in obsidian.json while Obsidian is closed.

	.EXAMPLE
		Enable-ObsidianCli -WhatIf
		Reports what would be written without touching the file.

	.EXAMPLE
		Enable-ObsidianCli -CreateIfMissing
		What the Bootstrap step runs: sets the flag, creating obsidian.json when Obsidian has not started yet.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter()]
		[string]$SettingsPath = (Join-Path $env:APPDATA 'obsidian\obsidian.json'),

		[Parameter()]
		[switch]$CreateIfMissing
	)

	if (Get-Process -Name 'obsidian' -ErrorAction SilentlyContinue) {
		Write-LogWarning "Obsidian is running - close it first! Obsidian rewrites [$SettingsPath] on every settings change and would discard the flag."
		return
	}

	if (-not (Test-Path -LiteralPath $SettingsPath)) {
		if (-not $CreateIfMissing) {
			Write-LogWarning "Obsidian settings file not found at [$SettingsPath] - start Obsidian once on this machine first (it creates the file), or run [Enable-ObsidianCli -CreateIfMissing]!"
			return
		}
		if ($PSCmdlet.ShouldProcess($SettingsPath, 'Create with "cli": true')) {
			New-Item -ItemType Directory -Path (Split-Path -Parent $SettingsPath) -Force | Out-Null
			Set-Content -LiteralPath $SettingsPath -Value '{"cli":true}' -NoNewline -Encoding utf8
			Write-LogSuccess "Obsidian CLI enabled! Created [$SettingsPath] - Obsidian fills in the rest on its first start."
		}
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
