# Configures power button, sleep button, lid close actions, and shutdown settings.
# Applies settings to ALL power schemes to prevent Windows from reverting them.
# Must be run as Administrator.
#
# powercfg action values
#	0 = Do nothing
#	1 = Sleep
#	2 = Hibernate
#	3 = Shut down
#	4 = Turn off display
# powercfg setting aliases:
#   SUB_BUTTONS  => Button and lid actions sub-group
#   PBUTTONACTION => Power button action
#   SBUTTONACTION => Sleep button action
#   LIDACTION     => Lid close action
function Set-PowerButtonActions {
	<#
	.SYNOPSIS
		Configures power button, sleep button, and lid-close actions.

	.DESCRIPTION
		Sets what happens when the power button is pressed, sleep button is pressed, or
		the laptop lid is closed (both on battery and when plugged in).
		Also controls Fast Startup, Sleep, and Hibernate features.

		With `-Auto`, reads all settings from `PowerButtonActions` in Configuration.psd1.
		Without `-Auto`, accepts individual parameters (e.g. `-PowerButtonOnBattery "ShutDown"`).
		Valid actions: "DoNothing", "Sleep", "Hibernate", "ShutDown".

		Applies settings to ALL power schemes to prevent Windows from overriding them.
		Requires administrator privileges.

	.PARAMETER Auto
		Reads all button and lid actions from Configuration.psd1.

	.PARAMETER PowerButtonOnBattery
		Action when power button is pressed on battery.

	.PARAMETER PowerButtonPluggedIn
		Action when power button is pressed while plugged in.

	.PARAMETER SleepButtonOnBattery
		Action when sleep button is pressed on battery.

	.PARAMETER SleepButtonPluggedIn
		Action when sleep button is pressed while plugged in.

	.PARAMETER LidCloseOnBattery
		Action when laptop lid is closed on battery.

	.PARAMETER LidClosePluggedIn
		Action when laptop lid is closed while plugged in.

	.PARAMETER DisableFastStartup
		Disable Windows Fast Startup (hybrid sleep).

	.PARAMETER DisableSleep
		Disable sleep mode.

	.PARAMETER DisableHibernate
		Disable hibernation mode.

	.EXAMPLE
		Set-PowerButtonActions -Auto
		Reads and applies all configured button actions.

	.EXAMPLE
		Set-PowerButtonActions -PowerButtonPluggedIn "ShutDown" -PowerButtonOnBattery "Sleep"
		Sets the power button actions for both power states.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Auto,

		[Parameter(Mandatory = $false)]
		[ValidateSet("DoNothing", "Sleep", "Hibernate", "ShutDown")]
		[string]$PowerButtonOnBattery,

		[Parameter(Mandatory = $false)]
		[ValidateSet("DoNothing", "Sleep", "Hibernate", "ShutDown")]
		[string]$PowerButtonPluggedIn,

		[Parameter(Mandatory = $false)]
		[ValidateSet("DoNothing", "Sleep", "Hibernate", "ShutDown")]
		[string]$SleepButtonOnBattery,

		[Parameter(Mandatory = $false)]
		[ValidateSet("DoNothing", "Sleep", "Hibernate", "ShutDown")]
		[string]$SleepButtonPluggedIn,

		[Parameter(Mandatory = $false)]
		[ValidateSet("DoNothing", "Sleep", "Hibernate", "ShutDown")]
		[string]$LidCloseOnBattery,

		[Parameter(Mandatory = $false)]
		[ValidateSet("DoNothing", "Sleep", "Hibernate", "ShutDown")]
		[string]$LidClosePluggedIn,

		[Parameter(Mandatory = $false)]
		[nullable[bool]]$DisableFastStartup,

		[Parameter(Mandatory = $false)]
		[nullable[bool]]$DisableSleep,

		[Parameter(Mandatory = $false)]
		[nullable[bool]]$DisableHibernate
	)

	Test-AdminPrivileges

	Write-LogTitle "Configuring Power Button & Lid Actions"

	# --- Resolve settings from configuration or parameters ---
	$defaults = @{
		PowerButtonOnBattery = "ShutDown"
		PowerButtonPluggedIn = "ShutDown"
		SleepButtonOnBattery = "DoNothing"
		SleepButtonPluggedIn = "DoNothing"
		LidCloseOnBattery    = "ShutDown"
		LidClosePluggedIn    = "DoNothing"
		DisableFastStartup   = $true
		DisableSleep         = $true
		DisableHibernate     = $true
	}

	if ($Auto) {
		$MachineType = DetermineMachineType
		Write-LogStep " Machine type => [$MachineType]" -NoLeadingNewline

		$machineConfig = $Configuration.PowerButtonActions[$MachineType]
		$nullableToggleKeys = @('DisableFastStartup', 'DisableSleep', 'DisableHibernate')

		if (-not $machineConfig) {
			Write-LogWarning "No configuration found for machine type [$MachineType], using defaults!"
			$machineConfig = @{}
		}

		# Config values serve as base, explicit parameters override
		foreach ($key in $defaults.Keys) {
			$paramValue = $PSBoundParameters[$key]
			if ($null -ne $paramValue) {
				# Explicit parameter wins
			}
			elseif ($machineConfig.ContainsKey($key)) {
				Set-Variable -Name $key -Value $machineConfig[$key]
			}
			elseif ($nullableToggleKeys -contains $key) {
				# Missing nullable toggles are treated as unmanaged.
				Set-Variable -Name $key -Value $null
			}
			else {
				Set-Variable -Name $key -Value $defaults[$key]
			}
		}
	}
	else {
		# No -Auto: use explicit parameters with hardcoded defaults
		foreach ($key in $defaults.Keys) {
			if (-not $PSBoundParameters.ContainsKey($key)) {
				Set-Variable -Name $key -Value $defaults[$key]
			}
		}
	}

	# --- Map friendly names to powercfg index values ---
	$actionMap = @{
		"DoNothing" = 0
		"Sleep"     = 1
		"Hibernate" = 2
		"ShutDown"  = 3
	}

	$actionLabel = @{ 0 = "Do nothing"; 1 = "Sleep"; 2 = "Hibernate"; 3 = "Shut down" }

	# --- Collect all power scheme GUIDs ---
	$schemeGuids = @()
	$schemeOutput = powercfg /list
	foreach ($line in $schemeOutput) {
		if ($line -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})") {
			$schemeGuids += $matches[1]
		}
	}

	if ($schemeGuids.Count -eq 0) {
		Write-LogError "No power schemes found!" -NoLeadingNewline
		return
	}

	# --- Get active scheme GUID for reading current values ---
	$activeSchemeGuid = $null
	$activeOutput = powercfg /getactivescheme
	if ($activeOutput -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})") {
		$activeSchemeGuid = $matches[1]
	}

	Write-LogSuccess "Found $($schemeGuids.Count) power scheme(s)!" -BlankLineAfter

	try {
		# --- Define the settings to apply ---
		$settings = @(
			@{ Name = "Power button (On battery)"; Setting = "PBUTTONACTION"; Type = "DC"; Value = $actionMap[$PowerButtonOnBattery] }
			@{ Name = "Power button (Plugged in)"; Setting = "PBUTTONACTION"; Type = "AC"; Value = $actionMap[$PowerButtonPluggedIn] }
			@{ Name = "Sleep button (On battery)"; Setting = "SBUTTONACTION"; Type = "DC"; Value = $actionMap[$SleepButtonOnBattery] }
			@{ Name = "Sleep button (Plugged in)"; Setting = "SBUTTONACTION"; Type = "AC"; Value = $actionMap[$SleepButtonPluggedIn] }
			@{ Name = "Lid close (On battery)"; Setting = "LIDACTION"; Type = "DC"; Value = $actionMap[$LidCloseOnBattery] }
			@{ Name = "Lid close (Plugged in)"; Setting = "LIDACTION"; Type = "AC"; Value = $actionMap[$LidClosePluggedIn] }
		)

		# --- Sub-group and setting GUIDs for registry queries ---
		$buttonsSubGroup = "4f971e89-eebd-4455-a8de-9e59040e7347"
		$settingGuids = @{
			"PBUTTONACTION" = "7648efa3-dd9c-4e3e-b566-50f929386280"
			"SBUTTONACTION" = "96996bc0-ad50-47ec-923b-6f41874dd9eb"
			"LIDACTION"     = "5ca83367-6e45-459f-a27b-476b1d01c936"
		}

		# --- Read current values from active scheme registry ---
		$powerSettingsRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes"
		$changedButtonSettings = $false

		foreach ($s in $settings) {
			$settingGuid = $settingGuids[$s.Setting]
			$regPath = "$powerSettingsRoot\$activeSchemeGuid\$buttonsSubGroup\$settingGuid"
			$valueName = if ($s.Type -eq "DC") { "DCSettingIndex" } else { "ACSettingIndex" }

			$currentValue = $null
			if (Test-Path $regPath) {
				$regEntry = Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction SilentlyContinue
				if ($regEntry) {
					$currentValue = $regEntry.$valueName
				}
			}

			if ($currentValue -eq $s.Value) {
				Write-LogWarning "$($s.Name) => [$($actionLabel[$s.Value])] - already set!" -NoLeadingNewline
			}
			else {
				# Apply to every power scheme
				foreach ($guid in $schemeGuids) {
					if ($s.Type -eq "DC") {
						powercfg /SETDCVALUEINDEX $guid SUB_BUTTONS $s.Setting $s.Value 2>&1 | Out-Null
					}
					else {
						powercfg /SETACVALUEINDEX $guid SUB_BUTTONS $s.Setting $s.Value 2>&1 | Out-Null
					}
				}

				# Also enforce via registry for all schemes
				foreach ($guid in $schemeGuids) {
					$regPathEnforce = "HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$guid\$buttonsSubGroup\$settingGuid"
					reg add $regPathEnforce /v $valueName /t REG_DWORD /d $($s.Value) /f 2>&1 | Out-Null
				}

				$changedButtonSettings = $true
				Write-LogSuccess "$($s.Name) => [$($actionLabel[$s.Value])]" -NoLeadingNewline
			}
		}

		# --- Re-activate the current scheme to force-apply changes ---
		if ($changedButtonSettings -and $activeSchemeGuid) {
			powercfg /S $activeSchemeGuid 2>&1 | Out-Null
		}

		# --- Fast Startup ---
		Write-Host ""
		if ($null -eq $DisableFastStartup) {
			Write-LogWarning "Fast Startup: Skipped (managed by Win11Debloat)" -NoLeadingNewline
		}
		else {
			$fastStartupPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
			$currentFastStartup = (Get-ItemProperty -Path $fastStartupPath -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
			$desiredFastStartup = if ($DisableFastStartup) { 0 } else { 1 }

			if ($currentFastStartup -eq $desiredFastStartup) {
				$label = if ($DisableFastStartup) { "Disabled" } else { "Enabled" }
				Write-LogWarning "Fast Startup: $label (already set)" -NoLeadingNewline
			}
			else {
				reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d $desiredFastStartup /f 2>&1 | Out-Null
				if ($DisableFastStartup) {
					Write-LogSuccess "Fast Startup: Disabled" -NoLeadingNewline
				}
				else {
					Write-LogSuccess "Fast Startup: Enabled" -NoLeadingNewline
				}
			}
		}

		# --- Hibernate ---
		$flyoutPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
		$currentHibernateOption = (Get-ItemProperty -Path $flyoutPath -Name ShowHibernateOption -ErrorAction SilentlyContinue).ShowHibernateOption
		$desiredHibernateOption = if ($DisableHibernate) { 0 } else { 1 }

		if ($currentHibernateOption -eq $desiredHibernateOption) {
			$label = if ($DisableHibernate) { "Disabled (hidden from Power menu)" } else { "Enabled" }
			Write-LogWarning "Hibernate: $label (already set)" -NoLeadingNewline
		}
		else {
			if ($DisableHibernate) {
				powercfg /hibernate off 2>&1 | Out-Null
				reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" /v ShowHibernateOption /t REG_DWORD /d 0 /f 2>&1 | Out-Null
				Write-LogSuccess "Hibernate: Disabled (hidden from Power menu)" -NoLeadingNewline
			}
			else {
				powercfg /hibernate on 2>&1 | Out-Null
				reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" /v ShowHibernateOption /t REG_DWORD /d 1 /f 2>&1 | Out-Null
				Write-LogSuccess "Hibernate: Enabled" -NoLeadingNewline
			}
		}

		# --- Sleep visibility in power menu ---
		$currentSleepOption = (Get-ItemProperty -Path $flyoutPath -Name ShowSleepOption -ErrorAction SilentlyContinue).ShowSleepOption
		$desiredSleepOption = if ($DisableSleep) { 0 } else { 1 }

		if ($currentSleepOption -eq $desiredSleepOption) {
			$label = if ($DisableSleep) { "Hidden from Power menu" } else { "Shown in Power menu" }
			Write-LogWarning "Sleep: $label (already set)" -NoLeadingNewline
		}
		else {
			if ($DisableSleep) {
				reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" /v ShowSleepOption /t REG_DWORD /d 0 /f 2>&1 | Out-Null
				Write-LogSuccess "Sleep: Hidden from Power menu" -NoLeadingNewline
			}
			else {
				reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" /v ShowSleepOption /t REG_DWORD /d 1 /f 2>&1 | Out-Null
				Write-LogSuccess "Sleep: Shown in Power menu" -NoLeadingNewline
			}
		}

		Write-LogSuccess "Power button and lid actions configured successfully!"
	}
	catch {
		Write-LogError "[$($_.Exception.Message)]" -NoLeadingNewline
		return
	}
}
