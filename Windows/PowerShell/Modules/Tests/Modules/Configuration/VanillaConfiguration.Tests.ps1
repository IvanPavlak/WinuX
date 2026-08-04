#Requires -Modules Pester

BeforeAll {
	# The raw base configuration, WITHOUT the Configuration.local.psd1 overlay.
	# This suite is the regression fence for the empty-by-default contract: a vanilla
	# WinuX install (no local override) must apply nothing user-specific, so every
	# personal section here has to stay empty. If one of these assertions fails, a
	# personal default leaked back into the tracked base.
	# (Get-RepositoryPath).Modules is <RepoRoot>\Windows\PowerShell\Modules; the base
	# config sits in its parent folder.
	$script:BaseConfig = Import-PowerShellDataFile (Join-Path (Split-Path (Get-RepositoryPath).Modules -Parent) "Configuration.psd1")
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
}
