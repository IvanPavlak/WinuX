#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Resolve-VSCodeProfilesConfig.ps1"
}

Describe "Resolve-VSCodeProfilesConfig" {
	It "falls back to the defaults when the section is missing" {
		$config = Resolve-VSCodeProfilesConfig -Configuration @{} -MachineType "PC" -RepoRoot "C:\Repo"

		$config.Root | Should -Be "C:\Repo\VSCode\Profiles"
		$config.UserData | Should -Be (Join-Path $env:APPDATA "Code\User")
		$config.SettingsSync | Should -BeFalse
		$config.Prune | Should -BeFalse
		$config.Entries.Count | Should -Be 0
		@($config.Selected).Count | Should -Be 0
	}

	It "expands the placeholders of Root and UserData" {
		$section = @{ VSCodeProfiles = @{ Root = "{RepoRoot}\Profiles"; UserData = "{User}\CodeData" } }
		$config = Resolve-VSCodeProfilesConfig -Configuration $section -MachineType "PC" -RepoRoot "C:\Repo"

		$config.Root | Should -Be "C:\Repo\Profiles"
		$config.UserData | Should -Be (Join-Path $env:USERPROFILE "CodeData")
	}

	It "keeps the catalogue order and defaults an entry's Target to its name" {
		$section = @{ VSCodeProfiles = @{ Catalogue = @(
					@{ Zeta = @{ Target = "Default" } }
					@{ Alpha = @{} }
				)
			}
		}
		$config = Resolve-VSCodeProfilesConfig -Configuration $section -MachineType "PC" -RepoRoot "C:\Repo"

		@($config.Entries.Keys) -join "," | Should -Be "Zeta,Alpha"
		$config.Entries["Zeta"].Target | Should -Be "Default"
		$config.Entries["Alpha"].Target | Should -Be "Alpha"
		$config.Entries["Alpha"].Source | Should -Be "C:\Repo\VSCode\Profiles\Alpha"
	}

	It "selects the machine type's own Deploy list over Default" {
		$section = @{ VSCodeProfiles = @{
				Catalogue = @(@{ One = @{} }, @{ Two = @{} })
				Deploy    = @{ Default = @("One"); Work = @("One", "Two") }
			}
		}

		(Resolve-VSCodeProfilesConfig -Configuration $section -MachineType "Work" -RepoRoot "C:\Repo").Selected -join "," | Should -Be "One,Two"
		(Resolve-VSCodeProfilesConfig -Configuration $section -MachineType "Laptop" -RepoRoot "C:\Repo").Selected -join "," | Should -Be "One"
	}

	It "selects nothing for a machine type with neither its own list nor a Default" {
		$section = @{ VSCodeProfiles = @{ Catalogue = @(@{ One = @{} }); Deploy = @{ Work = @("One") } } }

		@((Resolve-VSCodeProfilesConfig -Configuration $section -MachineType "PC" -RepoRoot "C:\Repo").Selected).Count | Should -Be 0
	}

	It "reports selected names the catalogue does not carry" {
		$section = @{ VSCodeProfiles = @{ Catalogue = @(@{ One = @{} }); Deploy = @{ Default = @("One", "Missing") } } }

		@((Resolve-VSCodeProfilesConfig -Configuration $section -MachineType "PC" -RepoRoot "C:\Repo").Unknown) | Should -Be @("Missing")
	}

	It "reads SettingsSync and Prune" {
		$section = @{ VSCodeProfiles = @{ SettingsSync = $true; Prune = $true } }
		$config = Resolve-VSCodeProfilesConfig -Configuration $section -MachineType "PC" -RepoRoot "C:\Repo"

		$config.SettingsSync | Should -BeTrue
		$config.Prune | Should -BeTrue
	}
}
