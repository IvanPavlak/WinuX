function Switch-AiProfile {
	<#
	.SYNOPSIS
		Switches this machine to another AI profile in one call: records the pick, redeploys the rules and the managed settings, then checks the machine.

	.DESCRIPTION
		A machine runs the AI profile its hostname maps to (Resolve-AiProfile). Switch-AiProfile
		moves it to another configured profile and keeps it there:

		  1. writes the profile name into the switch file, ai-profile.switch in the folder of
		     the managed-settings destination of AiHarnesses (C:\Program Files\ClaudeCode in the
		     base). Resolve-AiProfile reads it after the WINUX_AI_PROFILE override and before
		     the hostname map, so every later command in every shell (Bootstrap, the deploy
		     functions, Test-AiProfile) runs the switched profile. The folder is
		     administrator-owned: only an elevated shell changes the pick;
		  2. runs Deploy-AiArtifacts -Kind Rules, which links the profile's rules item and
		     rewrites the managed settings copy (the Plan pin, the ownership guard, the
		     repository policy hook, ai-profile.conf), on Windows and in WSL;
		  3. with -Full, runs Deploy-AiArtifacts for every kind instead, then
		     Deploy-AiMcpServers and Deploy-AiMarketplaces, so the profile's skills, MCP servers
		     and marketplaces replace the previous profile's too;
		  4. runs Test-AiProfile, which names the Plan to log in to when the logged-in one is
		     the previous profile's.

		-Reset removes the switch file, so the machine runs the profile of its hostname (or the
		default) again, and redeploys the same way. Without -Name and -Reset it prints the
		profile the machine runs, how it was picked and the switch file, then offers the
		configured profiles in a menu (Resolve-Selection), by the names AiProfiles.Profiles
		gives them, plus Reset while a switch is in effect: a pick switches as -Name or -Reset
		would, Enter changes nothing. Profile names are free: any key of AiProfiles.Profiles
		is a profile.

		WINUX_AI_PROFILE outranks the switch file. When it is set in the session, the switch
		still deploys the profile it was given: the variable is reported and removed from the
		session. One set in the user or machine environment is reported, since it would
		override the switch in every new shell.

		Requires administrator privileges (Test-AdminPrivileges) unless -WhatIf is given; they
		are checked first, before the report, the menu and anything written, so a refused
		switch leaves the machine as it was and a pick is made once, in the elevated shell.
		-WhatIf writes nothing and runs Deploy-AiArtifacts -WhatIf as the profile the
		switch would pick. After a switch every open Claude Code session must restart: a
		session keeps the login and the managed settings it started with.

	.PARAMETER Name
		The profile to switch to, one of AiProfiles.Profiles (case-insensitive, tab-completed).

	.PARAMETER Reset
		Removes the switch file: the machine runs the profile of its hostname, or the default.

	.PARAMETER Full
		Also redeploys every artifact kind, the MCP servers and the marketplaces.

	.EXAMPLE
		Switch-AiProfile Work
		Switches the machine to the Work profile and redeploys its rules and managed settings.

	.EXAMPLE
		Switch-AiProfile Personal -Full
		Switches to Personal and brings its skills, MCP servers and marketplaces over too.

	.EXAMPLE
		Switch-AiProfile -Reset
		Returns the machine to the profile its hostname maps to.

	.EXAMPLE
		Switch-AiProfile
		Prints the current profile and how it was picked, then offers the configured profiles in a menu.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Position = 0)]
		[ArgumentCompleter({
				param($commandName, $parameterName, $wordToComplete)
				@((Resolve-AiProfile).Profiles.Keys) | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object
			})]
		[string]$Name,

		[Parameter()]
		[switch]$Reset,

		[Parameter()]
		[switch]$Full
	)

	$whatIf = [bool]$WhatIfPreference

	# First of all: a refused switch leaves the machine as it was, and the elevated rerun replays
	# the typed command, so a pick made in the menu before it would have to be made twice.
	if (-not $whatIf) {
		Test-AdminPrivileges
	}

	if ($Name -and $Reset) {
		Write-LogError "Give a profile name or -Reset, not both!"
		return
	}

	$current = Resolve-AiProfile
	$configured = @($current.Profiles.Keys)
	if ($configured.Count -eq 0) {
		Write-LogWarning "No AI profile configured (AiProfiles.Profiles) - nothing to switch!"
		return
	}
	$currentLabel = if ($current.Enabled) { "[$($current.Name)] (picked by $($current.Source))" } else { "none" }

	# --- No argument: report, then offer the profiles in a menu --------------------------------
	if (-not $Name -and -not $Reset) {
		Write-LogTitle "AI Profile"
		foreach ($message in @($current.Warnings)) { Write-LogWarning $message }
		Write-LogStep "Profile => $currentLabel"
		if (-not $current.SwitchPath) {
			Write-LogStep "Configured => [$($configured -join ', ')]"
			Write-LogStep "Switch file => none (no harness has a managed-settings destination)"
			return
		}
		if ($current.Switched) {
			Write-LogStep "Switch file => [$($current.SwitchPath)] (set to [$($current.Switched)])"
		}
		else {
			Write-LogStep "Switch file => [$($current.SwitchPath)] (not set)"
		}

		# The profiles, by their configured names, and Reset while a switch is in effect (left
		# out when a profile carries that name: the profile wins, -Reset still resets).
		$options = @($configured)
		$offerReset = $current.Switched -and -not ($configured | Where-Object { $_ -eq 'Reset' })
		if ($offerReset) { $options += 'Reset' }
		$picked = Resolve-Selection `
			-OptionList $options `
			-MenuTitle "[Available AI Profiles]" `
			-PromptMessage "Enter the profile to switch to by number or name, or press [Enter] to change nothing" `
			-AllowEmptyPromptResponse:$true
		$picked = [string]($picked | Select-Object -First 1)
		if (-not $picked) { return }
		if ($offerReset -and $picked -eq 'Reset') { $Reset = $true } else { $Name = $picked }
	}

	if (-not $current.SwitchPath) {
		Write-LogError "No harness has a managed-settings destination (AiHarnesses) - there is no administrator-owned folder to keep the switch in!"
		return
	}

	$target = ''
	if ($Name) {
		$target = [string]($configured | Where-Object { $_ -eq $Name.Trim() } | Select-Object -First 1)
		if (-not $target) {
			Write-LogError "[$Name] is no configured AI profile (configured: $($configured -join ', '))!"
			return
		}
	}

	Write-LogTitle "Switching AI Profile"

	# What the machine runs once the switch file is written or removed.
	$after = if ($target) { Resolve-AiProfile -Override $target } else { Resolve-AiProfile -Override '' -SwitchPath '' }
	$afterLabel = if ($after.Enabled) { "[$($after.Name)]$(if ($Reset) { " (picked by $($after.Source))" })" } else { "none" }
	Write-LogStep "Profile => $currentLabel to $afterLabel"

	$sessionOverride = [string]$env:WINUX_AI_PROFILE
	foreach ($scope in @('User', 'Machine')) {
		if ([Environment]::GetEnvironmentVariable('WINUX_AI_PROFILE', [EnvironmentVariableTarget]::$scope)) {
			Write-LogWarning "WINUX_AI_PROFILE is set in the $($scope.ToLowerInvariant()) environment and outranks the switch in every new shell - remove it!"
		}
	}

	if ($whatIf) {
		if ($Reset) {
			Write-LogStep "Would remove the switch file => [$($current.SwitchPath)]"
		}
		else {
			Write-LogStep "Would write the switch file => [$($current.SwitchPath)] (set to [$target])"
		}
		if ($sessionOverride) {
			Write-LogWarning "WINUX_AI_PROFILE is set to [$sessionOverride] in this session and outranks the switch - a switch removes it from the session"
		}
		if (-not $after.Enabled) {
			Write-LogStep "No AI profile would be active - the deploy preview is skipped"
			return
		}
		# The preview deploys as the profile the switch would pick; the variable is put back.
		try {
			$env:WINUX_AI_PROFILE = $after.Name
			if ($Full) {
				Deploy-AiArtifacts -WhatIf
				Write-LogStep "Would also run => [Deploy-AiMcpServers, Deploy-AiMarketplaces]"
			}
			else {
				Deploy-AiArtifacts -Kind Rules -WhatIf
			}
		}
		finally {
			# Assigned, not Remove-Item: under -WhatIf a Remove-Item would only be reported.
			$env:WINUX_AI_PROFILE = if ($sessionOverride) { $sessionOverride } else { $null }
		}
		return
	}

	try {
		if ($Reset) {
			if (Test-Path -LiteralPath $current.SwitchPath) {
				Remove-Item -LiteralPath $current.SwitchPath -Force -ErrorAction Stop
			}
			Write-LogSuccess "Removed the switch file => [$($current.SwitchPath)]"
		}
		else {
			New-Item -ItemType Directory -Path (Split-Path -Parent $current.SwitchPath) -Force -ErrorAction Stop | Out-Null
			[IO.File]::WriteAllText($current.SwitchPath, "$target`n", [Text.UTF8Encoding]::new($false))
			Write-LogSuccess "Wrote the switch file => [$($current.SwitchPath)] (set to [$target])"
		}
	}
	catch {
		Write-LogError "The switch file could not be changed => [$($current.SwitchPath)] => $($_.Exception.Message)" -Exception $_
		return
	}

	if ($sessionOverride) {
		$env:WINUX_AI_PROFILE = $null
		Write-LogWarning "WINUX_AI_PROFILE was set to [$sessionOverride] in this session and outranks the switch - removed from the session"
	}

	if ($Full) {
		Deploy-AiArtifacts
		Deploy-AiMcpServers
		Deploy-AiMarketplaces
	}
	else {
		Deploy-AiArtifacts -Kind Rules
	}

	Test-AiProfile

	Write-LogWarning "Restart every open Claude Code session - a session keeps the login and the managed settings it started with!"
	if (-not $Full) {
		Write-LogStep "The skills, MCP servers and marketplaces are still the previous profile's - Switch-AiProfile$(if ($target) { " $target" } else { " -Reset" }) -Full brings them over"
	}
}
