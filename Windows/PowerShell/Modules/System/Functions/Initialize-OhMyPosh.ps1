function Initialize-OhMyPosh {
	<#
	.SYNOPSIS
		Resolves the oh-my-posh binary and initializes the prompt theme for this session.

	.DESCRIPTION
		Wraps the classic profile one-liner
		`oh-my-posh init pwsh --config <theme> | Invoke-Expression`
		with robust binary resolution so it works on machines where the installer's PATH
		entry has not (yet) reached the shell - freshly provisioned machines, failed winget
		PATH registration, or a different install scope than the machine the profile was
		tuned on.

		Resolution order: PATH (Get-Command), then the known install locations (winget EXE
		per-user and machine scope, WinGet portable links, Store alias). When a fallback
		location hits, its directory is prepended to this session's PATH so `oh-my-posh`
		also works as a plain command afterwards.

		Bootstrap additionally persists the EXE install locations onto the User PATH via
		`AutoPathAdditions` (Set-EnvironmentVariables -Auto), so on a provisioned machine
		the PATH lookup succeeds immediately and this function degenerates to the one-liner.

		When the binary is genuinely absent, prints a single install hint instead of an
		error on every prompt.

	.NOTES
		DOT-INVOKE this function from the profile (`. Initialize-OhMyPosh`). The theme init
		script defines the prompt in the CALLER's scope; a normal call would discard it when
		the function returns.

	.EXAMPLE
		. Initialize-OhMyPosh
		Resolves oh-my-posh and initializes the prompt for the current session.
	#>
	[CmdletBinding()]
	param()

	$OmpExe = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source

	if (-not $OmpExe) {
		$OmpCandidates = @(
			(Join-Path $env:LOCALAPPDATA "Programs\oh-my-posh\bin\oh-my-posh.exe")
			(Join-Path $env:ProgramFiles "oh-my-posh\bin\oh-my-posh.exe")
			(Join-Path ${env:ProgramFiles(x86)} "oh-my-posh\bin\oh-my-posh.exe")
			(Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\oh-my-posh.exe")
			(Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\oh-my-posh.exe")
		)
		$OmpExe = $OmpCandidates | Where-Object { $_ -and (Test-Path -Path $_) } | Select-Object -First 1

		if ($OmpExe) {
			# Self-heal this session so `oh-my-posh` resolves as a plain command from here on.
			$env:Path = (Split-Path -Path $OmpExe -Parent) + ";" + $env:Path
		}
	}

	if ($OmpExe) {
		& $OmpExe init pwsh --config $global:Configuration.Universal.OhMyPoshThemeFile | Invoke-Expression
	}
	else {
		Write-Host -ForegroundColor Yellow "=> Oh My Posh not found - prompt theming skipped! Install it with => winget install JanDeDobbeleer.OhMyPosh -s winget"
	}
}
