function Initialize-Configuration {
	<#
	.SYNOPSIS
		First-run writer that captures your personal identity and paths into Configuration.local.psd1.

	.DESCRIPTION
		WinuX ships a generic Configuration.psd1 (blank Git identity, placeholder paths) and never
		commits personal data. Your personal values live in a sibling Configuration.local.psd1 which
		Load-PathConfiguration deep-merges over the base at load time (see OpenSource.md section 15).
		Because the base file is never edited, pulling upstream (WinuX) updates into a fork never
		conflicts on configuration.

		Initialize-Configuration writes that override file from your input the first time you set the
		machine up. It records only the keys that differ from the generic base:
		- GitConfig.UserName / GitConfig.UserEmail (consumed by Install-Git)
		- BasePaths.<MachineType>.Dev / .User (the {Dev} / {User} placeholder roots)
		- HostnameToMachineType (maps THIS machine's hostname to a machine type)

		Values not supplied as parameters are requested interactively. In a non-interactive session
		missing values fall back to sensible defaults rather than prompting, so automated runs never
		hang. If the override already exists with a Git identity, the function does nothing unless
		-Force is given. The generated content is validated (it must parse) before it is written.

	.PARAMETER Owner
		Your GitHub username/owner (used to default the Git name and for messaging).

	.PARAMETER GitName
		The Git user.name to write into GitConfig.UserName.

	.PARAMETER GitEmail
		The Git user.email to write into GitConfig.UserEmail. Stored only in your local override.

	.PARAMETER DevPath
		Your development root (the {Dev} placeholder), e.g. "C:\Users\You\Development".

	.PARAMETER MachineType
		The machine type to map this hostname to and to set BasePaths for. Defaults to "Test".

	.PARAMETER ConfigPath
		Path to the base Configuration.psd1. Used only to locate Configuration.local.psd1 beside it.
		Defaults to the repository's own config.

	.PARAMETER LocalConfigPath
		Path to the override file to write. Defaults to Configuration.local.psd1 beside ConfigPath.

	.PARAMETER Force
		Rewrite the override even if it already contains a Git identity.

	.EXAMPLE
		Initialize-Configuration
		Prompts for owner, Git name/email, and dev path, then writes Configuration.local.psd1.

	.EXAMPLE
		Initialize-Configuration -GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"
		Non-interactive: writes the supplied values to the override without prompting.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[string]$Owner,
		[string]$GitName,
		[string]$GitEmail,
		[string]$DevPath,
		[string]$MachineType = "Test",
		[string]$ConfigPath,
		[string]$LocalConfigPath,
		[switch]$Force
	)

	# Locate the base config (…\Windows\PowerShell\Configuration.psd1) and the override beside it.
	# Get-RepositoryPath walks up to the folder that holds Configuration.psd1, so this is immune to
	# the file being moved to a different depth. -StartPath anchors the search on THIS function's own
	# location (not the helper's), which keeps the derivation correct when a copy is dot-sourced from
	# a test sandbox.
	if (-not $ConfigPath) {
		try {
			$powerShellDir = (Get-RepositoryPath -StartPath $PSScriptRoot).PowerShell
		}
		catch {
			Write-LogError "Could not locate Configuration.psd1 above '$PSScriptRoot'; pass -ConfigPath explicitly."
			return
		}
		$ConfigPath = Join-Path -Path $powerShellDir -ChildPath "Configuration.psd1"
	}
	if (-not $LocalConfigPath) {
		$LocalConfigPath = Join-Path -Path (Split-Path -Path $ConfigPath -Parent) -ChildPath "Configuration.local.psd1"
	}

	# Already personalized? (override exists with a non-blank Git identity)
	if ((Test-Path -Path $LocalConfigPath) -and -not $Force) {
		try {
			$existing = Import-PowerShellDataFile -Path $LocalConfigPath
			if (-not [string]::IsNullOrWhiteSpace($existing.GitConfig.UserName)) {
				Write-LogSuccess "Local configuration already exists at '$LocalConfigPath'. Use -Force to overwrite."
				return
			}
		}
		catch { }
	}

	# Interactive only when a real console is attached; otherwise keep supplied values / defaults.
	$interactive = (-not [System.Console]::IsInputRedirected) -and $Host.Name -ne 'Default Host'

	$ask = {
		param($Current, $Prompt, $Default, $IsInteractive)
		if (-not [string]::IsNullOrWhiteSpace($Current)) { return $Current }
		if (-not $IsInteractive) { return $Default }
		$label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
		$answer = Read-Host -Prompt $label
		if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
		return $answer
	}

	# Owner only exists to default the Git name, so resolve it (and risk an interactive prompt)
	# ONLY when GitName wasn't supplied. This keeps partial-argument calls prompt-free regardless
	# of host interactivity (e.g. -GitName given but -Owner omitted must never prompt for Owner).
	if ([string]::IsNullOrWhiteSpace($GitName)) {
		$Owner = & $ask $Owner "GitHub owner/username" $env:USERNAME $interactive
		$GitName = & $ask $GitName "Git user.name" $Owner $interactive
	}
	$GitEmail = & $ask $GitEmail "Git user.email" "" $interactive
	$defaultDev = Join-Path -Path $env:USERPROFILE -ChildPath "Development\GitHub"
	$DevPath = & $ask $DevPath "Development root path" $defaultDev $interactive
	$userHome = $env:USERPROFILE
	$hostName = $env:COMPUTERNAME

	# Escape double quotes so generated string literals stay valid.
	$q = { param($v) ($v -replace '"', '""') }

	# Build the override .psd1 - only the keys that differ from the generic base. This is
	# deep-merged over Configuration.psd1 by Load-PathConfiguration.
	$lines = @(
		'# Configuration.local.psd1 - YOUR personal overrides, deep-merged over Configuration.psd1'
		'# at load time. Gitignored in WinuX; keep it in your own fork (or just on this machine).'
		'# Written by Initialize-Configuration - edit freely; add any keys you want to override.'
		'@{'
		"`tGitConfig             = @{"
		"`t`tUserName  = `"$(& $q $GitName)`""
		"`t`tUserEmail = `"$(& $q $GitEmail)`""
		"`t}"
		"`tBasePaths             = @{"
		"`t`t$MachineType = @{ Dev = `"$(& $q $DevPath)`"; User = `"$(& $q $userHome)`" }"
		"`t}"
		"`tHostnameToMachineType = @{"
		"`t`t`"$(& $q $hostName)`" = `"$MachineType`""
		"`t}"
		'}'
	)
	$content = ($lines -join "`r`n") + "`r`n"

	# Validate the generated override parses before writing it.
	$tempFile = [System.IO.Path]::GetTempFileName()
	try {
		Set-Content -Path $tempFile -Value $content -NoNewline -Encoding utf8
		$null = Import-PowerShellDataFile -Path $tempFile
	}
	catch {
		Write-LogError "Generated override would not parse; aborting without changes. $($_.Exception.Message)"
		Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
		return
	}
	Remove-Item -Path $tempFile -ErrorAction SilentlyContinue

	if ($PSCmdlet.ShouldProcess($LocalConfigPath, "Write personal overrides")) {
		Set-Content -Path $LocalConfigPath -Value $content -NoNewline -Encoding utf8
		Write-LogSuccess "Wrote personal overrides to '$LocalConfigPath'."
		Write-LogSuccess "  Git identity : $GitName <$GitEmail>"
		Write-LogSuccess "  Dev root     : $DevPath  ($MachineType)"
		Write-LogSuccess "  Hostname map : $hostName => $MachineType"
	}
}
