#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiProfile.ps1"

	function New-ProfileConfig {
		@{
			AiProfiles = @{
				Hosts        = @{ "WORKSTATION-01" = "Work" }
				Default      = "Personal"
				DefaultOwner = ""
				Shared       = @("https://github.com/MyUser/Dotfiles.git")
				Profiles     = @{
					Personal = @{
						Rules      = "MyRules"
						Plan       = @{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000A" }
						Unattended = $true
						Autonomous = @("git@github.com:MyUser/MyProject.git")
					}
					Work     = @{
						Rules      = "MyWorkRules"
						Plan       = @(
							@{ Name = "Team"; OrgUuid = "11111111-1111-1111-1111-111111111111" }
							@{ Name = "Team Two"; OrgUuid = "22222222-2222-2222-2222-222222222222" }
						)
						McpServers = @()
						Deploy     = @("claude-code")
						Owns       = @("github.com/My-Org/*")
					}
				}
			}
		}
	}
}

Describe "Resolve-AiProfile" {
	It "is off with no profile configured" {
		$result = Resolve-AiProfile -Configuration @{} -HostName "ANY" -Override ""

		$result.Enabled | Should -BeFalse
		$result.Name | Should -BeNullOrEmpty
		$result.Profile | Should -BeNullOrEmpty
	}

	It "picks the hostname entry over the default" {
		$result = Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "workstation-01" -Override ""

		$result.Enabled | Should -BeTrue
		$result.Name | Should -Be "Work"
		$result.Source | Should -Be "hostname"
	}

	It "falls back to the default for an unmapped host" {
		$result = Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "DESKTOP-GAMING" -Override ""

		$result.Name | Should -Be "Personal"
		$result.Source | Should -Be "default"
		$result.DefaultOwner | Should -Be "Personal" -Because "an empty DefaultOwner is the Default profile"
	}

	It "lets the override win, matched case-insensitively, and ignores one naming no profile" {
		(Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "DESKTOP-GAMING" -Override "work").Name | Should -Be "Work"

		$ignored = Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "WORKSTATION-01" -Override "Nobody"
		$ignored.Name | Should -Be "Work"
		$ignored.Source | Should -Be "hostname"
		@($ignored.Warnings | Where-Object { $_ -like "*WINUX_AI_PROFILE*" }).Count | Should -Be 1
	}

	It "is off when no default is set and the host is unmapped" {
		$config = New-ProfileConfig
		$config.AiProfiles.Default = ""

		(Resolve-AiProfile -Configuration $config -HostName "DESKTOP-GAMING" -Override "").Enabled | Should -BeFalse
	}

	It "normalises the repository patterns the way the guard normalises an origin remote" {
		$result = Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "DESKTOP-GAMING" -Override ""

		$result.Shared | Should -Be @("github.com/myuser/dotfiles")
		$result.Profile.Autonomous | Should -Be @("github.com/myuser/myproject")
		$result.Profiles['Work'].Owns | Should -Be @("github.com/my-org/*")
	}

	It "normalises the Plan to lowercase UUIDs and one-word names, one entry or several" {
		$result = Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "WORKSTATION-01" -Override ""

		@($result.Profiles['Personal'].Plans)[0].OrgUuid | Should -Be "00000000-0000-0000-0000-00000000000a"
		@($result.Profile.Plans).Count | Should -Be 2
		@($result.Profile.Plans)[1].Name | Should -Be "Team-Two"
	}

	It "keeps 'left out' (all) apart from an empty list (none) for McpServers, Marketplaces and Deploy" {
		$result = Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "WORKSTATION-01" -Override ""

		$result.Profiles['Personal'].McpServers | Should -BeNullOrEmpty
		$null -eq $result.Profiles['Personal'].McpServers | Should -BeTrue
		$null -eq $result.Profile.McpServers | Should -BeFalse
		@($result.Profile.McpServers).Count | Should -Be 0
		$null -eq $result.Profile.Marketplaces | Should -BeTrue
		$result.Profile.Deploy | Should -Be @("claude-code")
	}

	It "keeps a Plan entry whose OrgUuid is not a UUID out of Plans and records it in PlanErrors, with a warning" {
		$config = New-ProfileConfig
		$config.AiProfiles.Profiles.Personal.Plan = @{ Name = "Max"; OrgUuid = "not-a-uuid" }

		$result = Resolve-AiProfile -Configuration $config -HostName "DESKTOP-GAMING" -Override ""

		@($result.Profile.Plans).Count | Should -Be 0
		@($result.Profile.PlanErrors).Count | Should -Be 1 -Because "a configured but unusable Plan must not look like no Plan"
		@($result.Warnings | Where-Object { $_ -like "*not a UUID*" }).Count | Should -Be 1
	}

	It "has no PlanErrors for a profile without a Plan or with a valid one" {
		$config = New-ProfileConfig
		$config.AiProfiles.Profiles.Personal.Plan = @{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000A" }

		$result = Resolve-AiProfile -Configuration $config -HostName "DESKTOP-GAMING" -Override ""

		@($result.Profile.PlanErrors).Count | Should -Be 0
		$result.Profile.Plans[0].OrgUuid | Should -Be "00000000-0000-0000-0000-00000000000a"
	}

	It "defaults the repository policy to branch, with Autonomous as the autonomous level's patterns" {
		$result = Resolve-AiProfile -Configuration (New-ProfileConfig) -HostName "DESKTOP-GAMING" -Override ""

		$result.Profile.DefaultPolicy | Should -Be "branch"
		@($result.Profile.Policies.Keys) | Should -Be @("autonomous", "branch", "draft", "readonly", "blocked") -Because "the levels are ordered from most to least trust, so the least trusting match is rendered last"
		$result.Profile.Policies["autonomous"] | Should -Be @("github.com/myuser/myproject")
		@($result.Profile.MergeWithoutChecks).Count | Should -Be 0
	}

	It "merges Policies with Autonomous, normalises their patterns and level names, and reads MergeWithoutChecks" {
		$config = New-ProfileConfig
		$config.AiProfiles.Profiles.Personal.Policies = @{
			Autonomous = @("https://github.com/MyUser/Other.git")
			readonly   = @("github.com/My-Org/*")
		}
		$config.AiProfiles.Profiles.Personal.DefaultPolicy = "Draft"
		$config.AiProfiles.Profiles.Personal.MergeWithoutChecks = @("github.com/MyUser/Other")

		$result = Resolve-AiProfile -Configuration $config -HostName "DESKTOP-GAMING" -Override ""

		$result.Profile.Policies["autonomous"] | Should -Be @("github.com/myuser/myproject", "github.com/myuser/other")
		$result.Profile.Autonomous | Should -Be @("github.com/myuser/myproject", "github.com/myuser/other")
		$result.Profile.Policies["readonly"] | Should -Be @("github.com/my-org/*")
		$result.Profile.DefaultPolicy | Should -Be "draft"
		$result.Profile.MergeWithoutChecks | Should -Be @("github.com/myuser/other")
		$result.Warnings | Should -BeNullOrEmpty
	}

	It "skips an unknown level with a warning and fails closed to readonly for a DefaultPolicy that is not a level" {
		$config = New-ProfileConfig
		$config.AiProfiles.Profiles.Personal.Policies = @{ autonomus = @("github.com/myuser/typo") }
		$config.AiProfiles.Profiles.Personal.DefaultPolicy = "autonomus"

		$result = Resolve-AiProfile -Configuration $config -HostName "DESKTOP-GAMING" -Override ""

		@($result.Profile.Policies.Values | ForEach-Object { $_ }) | Should -Not -Contain "github.com/myuser/typo"
		$result.Profile.DefaultPolicy | Should -Be "readonly" -Because "a typo must never invent a looser level"
		@($result.Warnings | Where-Object { $_ -like "*Policies names an unknown level*" }).Count | Should -Be 1
		@($result.Warnings | Where-Object { $_ -like "*DefaultPolicy is not a level*" }).Count | Should -Be 1
	}
}
