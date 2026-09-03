#Requires -Modules Pester

BeforeAll {
	# The raw base configuration, WITHOUT the Configuration.local.psd1 overlay.
	# This suite is the regression fence for the empty-by-default contract: a vanilla
	# WinuX install (no local override) must apply nothing user-specific, so every
	# personal section here has to stay empty. If one of these assertions fails, a
	# personal default leaked back into the tracked base.
	# (Get-RepositoryPath).Modules is <RepoRoot>\Windows\PowerShell\Modules; the base
	# config sits in its parent folder.
	$ModuleRoot = (Get-RepositoryPath).Modules
	$script:BaseConfig = Import-PowerShellDataFile (Join-Path (Split-Path $ModuleRoot -Parent) "Configuration.psd1")

	. "$ModuleRoot\Configuration\Functions\Test-ConfigurationKeyPath.ps1"
	. "$ModuleRoot\Configuration\Functions\Test-ConfigurationSchema.ps1"
}

Describe "Vanilla Configuration (empty-by-default contract)" {
	Context "Personal sections ship empty" {
		It "Should ship <Key> empty" -ForEach @(
			@{ Key = "Themes" }
			@{ Key = "WallpaperDarkSettings" }
			@{ Key = "WallpaperLightSettings" }
			@{ Key = "PowerPlans" }
			@{ Key = "PowerButtonActions" }
			@{ Key = "Locales" }
			@{ Key = "KeyboardLayouts" }
			@{ Key = "KeyboardLayoutSets" }
			@{ Key = "DisplayLanguages" }
			@{ Key = "NerdFonts" }
			@{ Key = "WakeOnLanConfig" }
			@{ Key = "PostgreSqlPasswords" }
			@{ Key = "AutoEnvironmentVariables" }
			@{ Key = "VisualEffects" }
			@{ Key = "TaskbarSettings" }
		) {
			$script:BaseConfig[$Key] | Should -BeOfType [hashtable]
			$script:BaseConfig[$Key].Count | Should -Be 0 -Because "$Key must stay empty in the tracked base"
		}

		It "Should ship <Key> as an empty list" -ForEach @(
			@{ Key = "WakeOnLanMachines" }
			@{ Key = "SpecialFolders" }
			@{ Key = "ExplorerOptions" }
			@{ Key = "AutoPathAdditions" }
			@{ Key = "TaskbarConfiguration" }
		) {
			@($script:BaseConfig[$Key]).Count | Should -Be 0 -Because "$Key must stay empty in the tracked base"
		}

		It "Should ship <Key> blank" -ForEach @(
			@{ Key = "DefaultWSLDistribution" }
			@{ Key = "DefaultWSLUsername" }
			@{ Key = "DefaultWakeOnLanMachine" }
			@{ Key = "DefaultLocale" }
			@{ Key = "DefaultKeyboardLayoutSet" }
			@{ Key = "DefaultDisplayLanguage" }
			@{ Key = "DefaultNerdFont" }
			@{ Key = "DotnetEFVersion" }
		) {
			$script:BaseConfig[$Key] | Should -BeNullOrEmpty -Because "$Key must stay blank in the tracked base"
		}

		It "Should ship Universal.DefaultBrowser blank" {
			$script:BaseConfig.Universal.DefaultBrowser | Should -BeNullOrEmpty
		}

		It "Should ship the personal executable paths blank" {
			foreach ($key in @(
					"TrainingFile", "LeagueOfLegendsExe", "SteamExe", "RiseupVpnExe", "DbeaverExe",
					"TeamViewerExe", "FoundryVTTExe", "NotepadPlusPlusExe", "VisualStudio2026Exe", "VirtualBoxExe")) {
				$script:BaseConfig.Universal[$key] | Should -BeNullOrEmpty -Because "Universal.$key must stay blank in the tracked base"
			}
		}

		It "Should ship an empty PersonalSteps list" {
			@($script:BaseConfig.BootstrapConfig.PersonalSteps).Count | Should -Be 0
		}

		It "Should ship blank Git identity" {
			$script:BaseConfig.GitConfig.UserName | Should -BeNullOrEmpty
			$script:BaseConfig.GitConfig.UserEmail | Should -BeNullOrEmpty
		}
	}

	Context "Framework essentials stay in the base" {
		It "Should keep the PowerShell profile symlink (persists WinuX into new shells)" {
			$links = $script:BaseConfig.PathTemplates.SymbolicLinks
			$links.PowerShell.Profile.Path | Should -Not -BeNullOrEmpty
			$links.PowerShell.Profile.Target | Should -Match "Microsoft\.PowerShell_profile\.ps1"
			$links.PowerShell.Configuration.Target | Should -Match "Configuration\.psd1"
		}

		It "Should keep the PowerToys FancyZones symlink trio" {
			$powerToys = $script:BaseConfig.PathTemplates.SymbolicLinks.PowerToys
			foreach ($key in @("Settings", "CustomLayouts", "LayoutHotkeys")) {
				$powerToys[$key].Path | Should -Not -BeNullOrEmpty -Because "the FancyZones $key link backs the window machinery"
			}
		}

		It "Should keep only the framework symlink groups" {
			@($script:BaseConfig.PathTemplates.SymbolicLinks.Keys) | Sort-Object | Should -Be @("PowerShell", "PowerToys")
		}

		It "Should keep all five browser definitions" {
			@($script:BaseConfig.Universal.Browsers.Keys) | Sort-Object | Should -Be @("Brave", "Chrome", "Edge", "Firefox", "Tor")
		}

		It "Should keep the Kill-All defaults" {
			$script:BaseConfig.Universal.TerminateProcessNames | Should -Not -BeNullOrEmpty
			$script:BaseConfig.Universal.VisibleWindowExclusions | Should -Contain "PowerToys.FancyZones"
		}
	}

	Context "Display-aware window sizing" {
		# All three sections resolve through engine fallbacks, and an explicit config value beats
		# the fallback - so the base values and the built-in defaults must agree or the documented
		# defaults become a lie for anyone reading the resolvers.
		It "Should ship CenterTerminalSizing in the keyed shape" {
			# Keyed, not flat: Resolve-CenterTerminalSizing treats a section carrying TargetWidthPx
			# as the legacy flat shape and returns it whole, which would bypass the rows entirely.
			$sizing = $script:BaseConfig.CenterTerminalSizing
			$sizing | Should -BeOfType [hashtable]
			$sizing.ContainsKey('TargetWidthPx') | Should -BeFalse -Because "a TargetWidthPx at section level is the legacy flat shape"
			$sizing.ContainsKey('Default') | Should -BeTrue
		}

		It "Should ship CenterTerminalSizing.Default.<Key> as <Expected>" -ForEach @(
			@{ Key = "TargetWidthPx"; Expected = 1376 }
			@{ Key = "TargetHeightPx"; Expected = 700 }
			@{ Key = "MinWidthPercent"; Expected = 25 }
			@{ Key = "MaxWidthPercent"; Expected = 72 }
			@{ Key = "MinHeightPercent"; Expected = 35 }
			@{ Key = "MaxHeightPercent"; Expected = 75 }
		) {
			# 1376x700 is what 40% x 50% yields on a 3440x1440 ultrawide - the anchor that keeps
			# the vanilla terminal size unchanged from before the section existed.
			$script:BaseConfig.CenterTerminalSizing.Default[$Key] | Should -Be $Expected
		}

		It "Should ship ResizeWindowsPercent.Default matching Resolve-ResizeWindowsPercent's built-in" {
			$script:BaseConfig.ResizeWindowsPercent.Default | Should -Be 70
		}

		It "Should ship no personal SmallDisplay row" {
			# A gentler shrink on a laptop panel is a personal tuning choice; the tracked base
			# must behave the same on every display.
			$script:BaseConfig.ResizeWindowsPercent.ContainsKey('SmallDisplay') | Should -BeFalse
			$script:BaseConfig.CenterTerminalSizing.ContainsKey('SmallDisplay') | Should -BeFalse
		}

		It "Should ship SnapInsetPercent matching Get-WindowInsetPercent's built-in" {
			$script:BaseConfig.SnapInsetPercent | Should -Be 0.05
		}
	}

	Context "Workspace benchmark opt-in" {
		# Measurement is opt-in: a vanilla open must print exactly what it printed before the
		# benchmark existed, so the base ships the key present but disabled.
		It "Should ship WorkspaceBenchmark disabled, with the Table display and ten rows" {
			$benchmark = $script:BaseConfig.WorkspaceBenchmark
			$benchmark | Should -BeOfType [hashtable]
			$benchmark.Enabled | Should -BeFalse
			$benchmark.Display | Should -Be 'Table'
			$benchmark.Last | Should -Be 10
		}
	}

	Context "FancyZones apply method" {
		# Zone layouts reach FancyZones through applied-layouts.json by default; "Hotkeys" is the
		# escape hatch back to the desktop-switching shortcut pass.
		It "Should ship FancyZonesApplyMethod as File" {
			$script:BaseConfig.FancyZonesApplyMethod | Should -Be 'File'
		}

		It "Should ship WorkspaceLayoutPipelining enabled" {
			$script:BaseConfig.WorkspaceLayoutPipelining | Should -BeTrue
		}
	}

	Context "Schema validation of the untouched base" {
		# The vanilla base must be a VALID configuration, not a broken one: the schema
		# validator may only require framework keys. The two GitConfig entries are the
		# documented exception - the base ships them blank and Initialize-Configuration
		# writes them into Configuration.local.psd1 on the first run.
		It "Should report only the first-run Git identity keys" {
			$warnings = @()
			Test-ConfigurationSchema -Configuration $script:BaseConfig -WarningVariable warnings -WarningAction SilentlyContinue

			$text = $warnings -join "`n"
			$text | Should -Match "GitConfig\.UserName"
			$text | Should -Match "GitConfig\.UserEmail"

			# No user-specific section may be treated as required - they all ship empty.
			foreach ($optIn in @("DefaultLocale", "Locales", "KeyboardLayouts", "Themes", "NerdFonts", "WakeOnLan", "SpecialFolders", "TaskbarConfiguration", "DefaultBrowser")) {
				$text | Should -Not -Match $optIn -Because "$optIn ships empty by design and must not be a required key"
			}
		}
	}

	Context "Bootstrap step toggles" {
		It "Should carry the Steps section with the WSL machine-type map" {
			$steps = $script:BaseConfig.BootstrapConfig.Steps
			$steps | Should -BeOfType [hashtable]
			$steps.WSL.Default | Should -BeTrue
			$steps.WSL.Test | Should -BeFalse
		}

		It "Should no longer carry the deprecated toggles" {
			$script:BaseConfig.BootstrapConfig.ContainsKey("PromptForActivation") | Should -BeFalse
			$script:BaseConfig.BootstrapConfig.ContainsKey("PromptForDebloat") | Should -BeFalse
			$script:BaseConfig.BootstrapConfig.ContainsKey("WSLSetup") | Should -BeFalse
		}
	}

	Context "Set-SystemTheme step toggles" {
		# The base spells every step out, and an explicit config value beats the
		# resolver's built-in default - so the two must agree or the documented
		# defaults become a lie for anyone reading Resolve-SystemThemeSteps.
		It "Should ship <Key> as <Expected>, matching the Resolve-SystemThemeSteps default" -ForEach @(
			@{ Key = "RefreshBrowserTabs"; Expected = $false }
			@{ Key = "RestartExplorer"; Expected = $true }
			@{ Key = "SetWallpaper"; Expected = $true }
			@{ Key = "SetLockScreenWallpaper"; Expected = $true }
		) {
			$steps = $script:BaseConfig.SystemTheme.Steps
			$steps | Should -BeOfType [hashtable]
			$steps[$Key] | Should -Be $Expected -Because "the base value and the built-in default must not drift"
		}

		It "Should carry no step the resolver does not know about" {
			@($script:BaseConfig.SystemTheme.Steps.Keys) | Sort-Object |
				Should -Be @("RefreshBrowserTabs", "RestartExplorer", "SetLockScreenWallpaper", "SetWallpaper")
		}
	}
}
