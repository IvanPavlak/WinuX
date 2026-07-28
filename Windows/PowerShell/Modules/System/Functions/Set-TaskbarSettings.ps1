function Set-TaskbarSettings {
	<#
	.SYNOPSIS
		Applies the Settings > Personalisation > Taskbar page from configuration.

	.DESCRIPTION
		Reads per-control values from `TaskbarSettings` in Configuration.psd1 /
		Configuration.local.psd1 and applies them - the programmatic equivalent of walking
		the Settings > Personalisation > Taskbar page top to bottom. Every key mirrors one
		control on that page one-to-one: checkbox/toggle controls take $true (on) or $false
		(off), dropdown controls take one of the named tokens listed for them (case
		insensitive, PascalCase of the dropdown label). Keys left out of the configuration
		are not touched, and when the section is absent or empty the function changes
		NOTHING - the machine keeps its current taskbar settings. This keeps the upstream
		default vanilla; a fork opts in via its local configuration.

		Every managed control is a per-user registry value under HKCU. Most are DWords: most
		of those live in Explorer's `Advanced` key, while Search, Resume, the touch keyboard,
		"Emoji and more", and the pen menu each live in their own key, which is created when
		missing. "Automatically hide the taskbar" is the one exception in FORM only - it is a
		single bit inside Explorer's `StuckRects3` binary blob, read and rewritten in place so
		the surrounding bytes are preserved. Explorer owns that blob and cannot be handed a
		synthesized one, so an unreadable value skips the control instead of fabricating it.

		Explorer reads all of these on startup only, so Restart-Explorer runs once when at
		least one value was actually written; when every write fails the function reports it
		and skips the restart. Deliberately NOT done through SHAppBarMessage, which is what
		the settings page uses for auto-hide: that sets the state inside the running Explorer
		process, which only persists it on a graceful exit, so the restart this function
		performs for the other controls would throw the change away.

		Idempotent - compares every configured control against the current state and returns
		early when nothing needs to change. When changes are applied, every managed control is
		reported on its own line: green when a toggle is on, red when a toggle is off, white
		with the selected token for a dropdown, yellow [skipped] when already at the configured
		value. Unknown keys and invalid values are skipped with a warning.

	.EXAMPLE
		Set-TaskbarSettings
		Applies every control configured in the TaskbarSettings section.
	#>
	Write-LogTitle "Setting Taskbar Settings"

	$desiredSettings = $Configuration.TaskbarSettings
	if (-not ($desiredSettings -is [hashtable]) -or $desiredSettings.Count -eq 0) {
		Write-LogWarning "TaskbarSettings is not configured - leaving the taskbar settings as-is!"
		return
	}

	# One entry per control on the Taskbar settings page, in page order (Taskbar items ->
	# System tray icons -> Taskbar behaviours) rather than alphabetically, so the reported
	# rows read like the page itself. "Toggle" controls are the checkboxes and On/Off
	# switches; "Choice" controls are the dropdowns, whose tokens are the PascalCase dropdown
	# labels mapped to the value Windows stores; "Flag" is a single bit inside a binary value
	# Explorer owns. Taskbar alignment accepts both the British (Centre) and American (Center)
	# spelling, since the label follows the display language.
	$explorerAdvancedPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
	$textInputPath = "HKCU:\Software\Microsoft\TabletTip\1.7"

	$settingDefinitions = @(
		# --- Taskbar items ---
		@{ Key = "Search"; Kind = "Choice"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; Choices = [ordered]@{ Hide = 0; SearchIconOnly = 1; SearchBox = 2; SearchIconAndLabel = 3 } }
		@{ Key = "TaskView"; Kind = "Toggle"; Path = $explorerAdvancedPath; Name = "ShowTaskViewButton"; OnValue = 1; OffValue = 0 }
		@{ Key = "Resume"; Kind = "Toggle"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration"; Name = "IsResumeAllowed"; OnValue = 1; OffValue = 0 }

		# --- System tray icons ---
		@{ Key = "EmojiAndMore"; Kind = "Choice"; Path = $textInputPath; Name = "EmojiAndMoreIconVisibilityState"; Choices = [ordered]@{ Never = 0; WhileTyping = 1; Always = 2 } }
		@{ Key = "PenMenu"; Kind = "Toggle"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace"; Name = "PenWorkspaceButtonDesiredVisibility"; OnValue = 1; OffValue = 0 }
		@{ Key = "TouchKeyboard"; Kind = "Choice"; Path = $textInputPath; Name = "TipbandDesiredVisibility"; Choices = [ordered]@{ Never = 0; Always = 1; WhenNoKeyboardAttached = 2 } }

		# --- Taskbar behaviours ---
		@{ Key = "TaskbarAlignment"; Kind = "Choice"; Path = $explorerAdvancedPath; Name = "TaskbarAl"; Choices = [ordered]@{ Left = 0; Centre = 1; Center = 1 } }
		@{ Key = "AutomaticallyHideTheTaskbar"; Kind = "Flag"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"; Name = "Settings"; ByteIndex = 8; BitMask = 0x01 }
		@{ Key = "ShowBadgesOnTaskbarApps"; Kind = "Toggle"; Path = $explorerAdvancedPath; Name = "TaskbarBadges"; OnValue = 1; OffValue = 0 }
		@{ Key = "ShowFlashingOnTaskbarApps"; Kind = "Toggle"; Path = $explorerAdvancedPath; Name = "TaskbarFlashing"; OnValue = 1; OffValue = 0 }
		@{ Key = "ShowTaskbarOnAllDisplays"; Kind = "Toggle"; Path = $explorerAdvancedPath; Name = "MMTaskbarEnabled"; OnValue = 1; OffValue = 0 }
		@{ Key = "TaskbarAppsOnMultipleDisplays"; Kind = "Choice"; Path = $explorerAdvancedPath; Name = "MMTaskbarMode"; Choices = [ordered]@{ AllTaskbars = 0; MainTaskbarAndTaskbarWhereWindowIsOpen = 1; TaskbarWhereWindowIsOpen = 2 } }
		@{ Key = "ShareAnyWindowFromTaskbar"; Kind = "Toggle"; Path = $explorerAdvancedPath; Name = "TaskbarSn"; OnValue = 1; OffValue = 0 }
		@{ Key = "SelectFarCornerToShowDesktop"; Kind = "Toggle"; Path = $explorerAdvancedPath; Name = "TaskbarSd"; OnValue = 1; OffValue = 0 }
		@{ Key = "CombineTaskbarButtonsAndHideLabels"; Kind = "Choice"; Path = $explorerAdvancedPath; Name = "TaskbarGlomLevel"; Choices = [ordered]@{ Always = 0; WhenTaskbarIsFull = 1; Never = 2 } }
		@{ Key = "CombineTaskbarButtonsAndHideLabelsOnOtherTaskbars"; Kind = "Choice"; Path = $explorerAdvancedPath; Name = "MMTaskbarGlomLevel"; Choices = [ordered]@{ Always = 0; WhenTaskbarIsFull = 1; Never = 2 } }
		@{ Key = "ShowSmallerTaskbarButtons"; Kind = "Choice"; Path = $explorerAdvancedPath; Name = "IconSizePreference"; Choices = [ordered]@{ Always = 0; Never = 1; WhenTaskbarIsFull = 2 } }
	)

	# --- Typo protection: warn about configured keys that match no known control ---
	$knownKeys = $settingDefinitions.Key
	foreach ($configuredKey in $desiredSettings.Keys) {
		if ($configuredKey -notin $knownKeys) {
			Write-LogWarning "Unknown TaskbarSettings key [$configuredKey] - skipping!"
		}
	}

	# --- Resolve every configured control to a target value, dropping invalid ones ---
	$settingStates = @()
	foreach ($definition in $settingDefinitions | Where-Object { $desiredSettings.ContainsKey($_.Key) }) {
		$configuredValue = $desiredSettings[$definition.Key]

		if ($definition.Kind -eq "Choice") {
			# Resolve the token case insensitively so the config can use any casing, and report
			# the canonical spelling from the definition rather than whatever was typed
			$matchedToken = @($definition.Choices.Keys | Where-Object { $_ -eq "$configuredValue" })
			if ($matchedToken.Count -eq 0) {
				Write-LogWarning "TaskbarSettings [$($definition.Key)] has invalid value [$configuredValue] - expected one of [$($definition.Choices.Keys -join ', ')] - skipping!"
				continue
			}
			$targetValue = $definition.Choices[$matchedToken[0]]
			$label = $matchedToken[0]
			$rowStyle = "Step"
		}
		else {
			# Toggle and Flag are both booleans in the configuration; only the shape of the
			# registry value carrying them differs
			if ($configuredValue -isnot [bool]) {
				Write-LogWarning "TaskbarSettings [$($definition.Key)] expects `$true or `$false - skipping!"
				continue
			}
			if ($definition.Kind -eq "Flag") {
				$targetValue = $configuredValue
			}
			else {
				$targetValue = if ($configuredValue) { $definition.OnValue } else { $definition.OffValue }
			}
			$label = if ($configuredValue) { "on" } else { "off" }
			$rowStyle = if ($configuredValue) { "Success" } else { "Error" }
		}

		if ($definition.Kind -eq "Flag") {
			# Explorer owns the surrounding bytes of this blob, so a missing value cannot be
			# synthesized the way a lone DWord can - skip rather than fabricate one
			try {
				$flagBytes = Get-ItemPropertyValue -Path $definition.Path -Name $definition.Name -ErrorAction Stop
				$currentValue = ($flagBytes[$definition.ByteIndex] -band $definition.BitMask) -ne 0
			}
			catch {
				Write-LogWarning "TaskbarSettings [$($definition.Key)] could not read [$($definition.Path)\$($definition.Name)] - skipping!"
				continue
			}
		}
		else {
			try {
				$currentValue = Get-ItemPropertyValue -Path $definition.Path -Name $definition.Name -ErrorAction Stop
			}
			catch {
				# Value or key missing - the control is at its implicit Windows default, so write
				# it explicitly to make the state deterministic
				$currentValue = $null
			}
		}

		$settingStates += @{
			Definition  = $definition
			TargetValue = $targetValue
			Label       = $label
			RowStyle    = $rowStyle
			NeedsChange = ($currentValue -ne $targetValue)
		}
	}

	if ($settingStates.Count -eq 0) {
		Write-LogWarning "TaskbarSettings contains no valid control values - leaving the taskbar settings as-is!"
		return
	}

	$pendingChanges = @($settingStates | Where-Object { $_.NeedsChange })
	if ($pendingChanges.Count -eq 0) {
		Write-LogWarning "Taskbar settings already configured!"
		return
	}

	# --- Apply every control: green = toggle on, red = toggle off, white = dropdown token ---
	$appliedChanges = 0
	foreach ($settingState in $settingStates) {
		$definition = $settingState.Definition

		if (-not $settingState.NeedsChange) {
			Write-LogStep " $($definition.Key) => [skipped]" -Style Warning
			continue
		}

		try {
			if ($definition.Kind -eq "Flag") {
				# Read-modify-write: only the configured bit changes, every other byte of
				# Explorer's blob is written back exactly as it was found
				$flagBytes = Get-ItemPropertyValue -Path $definition.Path -Name $definition.Name -ErrorAction Stop
				$flagByte = $flagBytes[$definition.ByteIndex]
				$flagBytes[$definition.ByteIndex] = if ($settingState.TargetValue) { $flagByte -bor $definition.BitMask } else { $flagByte -band ($definition.BitMask -bxor 0xFF) }
				Set-ItemProperty -Path $definition.Path -Name $definition.Name -Value $flagBytes -Type Binary -Force
			}
			else {
				if (-not (Test-Path $definition.Path)) {
					New-Item -Path $definition.Path -Force | Out-Null
				}
				Set-ItemProperty -Path $definition.Path -Name $definition.Name -Value $settingState.TargetValue -Type DWord -Force
			}

			$appliedChanges++
			Write-LogStep " $($definition.Key) => [$($settingState.Label)]" -Style $settingState.RowStyle
		}
		catch {
			Write-LogError "Failed to set taskbar setting [$($definition.Key)]: $($_.Exception.Message)"
		}
	}

	if ($appliedChanges -eq 0) {
		Write-LogWarning "No taskbar settings could be applied!"
		return
	}

	# Explorer reads all of these on startup only. The restart is also what makes the
	# auto-hide bit take: killing Explorer stops it persisting its own in-memory state over
	# the value just written, and the fresh instance reads the blob back.
	Restart-Explorer

	Write-LogSuccess "Taskbar settings configured!"
}
