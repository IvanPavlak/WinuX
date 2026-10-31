#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\ConvertTo-AiManagedSettings.ps1"

	$script:Template = @'
{
	"forceLoginMethod": "claudeai",
	"hooks": {
		"PreToolUse": [
			{ "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"{ManagedDir}/hooks/policy.sh\"" } ] }
		]
	}
}
'@

	function New-ActiveProfile([object[]]$Plans) {
		$selected = @{
			Name       = "Personal"
			Plans      = $Plans
			Unattended = $true
			Autonomous = @("github.com/myuser/myproject")
			Owns       = @()
		}
		@{
			Enabled      = $true
			Name         = "Personal"
			Profile      = $selected
			Profiles     = [ordered]@{
				Personal = $selected
				Work     = @{ Name = "Work"; Owns = @("github.com/my-org/*"); Autonomous = @("github.com/my-org/never-listed") }
			}
			Shared       = @("github.com/myuser/dotfiles")
			DefaultOwner = "Personal"
		}
	}
}

Describe "ConvertTo-AiManagedSettings" {
	It "only replaces the token when no profile is active, and writes no ai-profile.conf" {
		$result = ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "C:\Program Files\ClaudeCode"

		$result.Problems | Should -BeNullOrEmpty
		$result.ProfileConf | Should -BeNullOrEmpty
		$document = $result.Settings | ConvertFrom-Json -AsHashtable
		$document.hooks.PreToolUse[0].hooks[0].command | Should -Be 'bash "C:/Program Files/ClaudeCode/hooks/policy.sh"'
		$document.ContainsKey('forceLoginOrgUUID') | Should -BeFalse
		$document.hooks.ContainsKey('UserPromptSubmit') | Should -BeFalse
	}

	It "pins the profile's one Plan as a string and wires the guard into both events" {
		$aiProfile = New-ActiveProfile @(@{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000a" })

		$result = ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile
		$document = $result.Settings | ConvertFrom-Json -AsHashtable

		$document.forceLoginOrgUUID | Should -Be "00000000-0000-0000-0000-00000000000a"
		@($document.hooks.PreToolUse).Count | Should -Be 3 -Because "the guard and the policy hook are appended after the item's own hook"
		$document.hooks.PreToolUse[1].matcher | Should -Be "*"
		$document.hooks.PreToolUse[1].hooks[0].command | Should -Be 'bash "/etc/claude-code/ai-ownership-guard.sh" PreToolUse'
		$document.hooks.PreToolUse[2].matcher | Should -Be "*" -Because "readonly also stops the file tools"
		$document.hooks.PreToolUse[2].hooks[0].command | Should -Be 'bash "/etc/claude-code/ai-repository-policy.sh"'
		@($document.hooks.UserPromptSubmit).Count | Should -Be 1
		$document.hooks.UserPromptSubmit[0].hooks[0].command | Should -Be 'bash "/etc/claude-code/ai-ownership-guard.sh" UserPromptSubmit'
	}

	It "writes the repository policy lines: default-policy, every level's patterns most trust first, and merge-without-checks" {
		$aiProfile = New-ActiveProfile @(@{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000a" })
		$policies = [ordered]@{ autonomous = @("github.com/myuser/myproject"); branch = @("github.com/myuser/*"); draft = @(); readonly = @("github.com/myuser/legacy"); blocked = @() }
		$aiProfile.Profile.Policies = $policies
		$aiProfile.Profile.DefaultPolicy = "readonly"
		$aiProfile.Profile.MergeWithoutChecks = @("github.com/myuser/myproject")

		$lines = @((ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile).ProfileConf -split "`n" | Where-Object { $_ })

		$lines | Should -Contain "default-policy readonly"
		$lines | Should -Contain "merge-without-checks github.com/myuser/myproject"
		$policyLines = @($lines | Where-Object { $_ -like "policy *" })
		$policyLines | Should -Be @("policy autonomous github.com/myuser/myproject", "policy branch github.com/myuser/*", "policy readonly github.com/myuser/legacy") -Because "the hooks take the last matching line, so the least trusting level must come last"
		[array]::IndexOf($lines, "autonomous github.com/myuser/myproject") | Should -BeLessThan ([array]::IndexOf($lines, $policyLines[0])) -Because "an autonomous line after a policy line would win over it"
	}

	It "writes default-policy branch for a profile that sets no repository policy" {
		$aiProfile = New-ActiveProfile @(@{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000a" })

		$lines = (ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile).ProfileConf -split "`n"

		$lines | Should -Contain "default-policy branch"
		@($lines | Where-Object { $_ -like "merge-without-checks *" }).Count | Should -Be 0
	}

	It "pins several Plans as an array" {
		$aiProfile = New-ActiveProfile @(
			@{ Name = "Team"; OrgUuid = "11111111-1111-1111-1111-111111111111" }
			@{ Name = "Max"; OrgUuid = "22222222-2222-2222-2222-222222222222" }
		)

		$document = (ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile).Settings | ConvertFrom-Json -AsHashtable

		@($document.forceLoginOrgUUID) | Should -Be @("11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222")
	}

	It "writes ai-profile.conf with every profile's owns lines and only the active profile's autonomous lines" {
		$aiProfile = New-ActiveProfile @(@{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000a" })

		$lines = (ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile).ProfileConf -split "`n" | Where-Object { $_ }

		$lines[0] | Should -BeLike "#*do not edit."
		$lines | Should -Contain "profile Personal"
		$lines | Should -Contain "default-owner Personal"
		$lines | Should -Contain "unattended on"
		$lines | Should -Contain "plan Max 00000000-0000-0000-0000-00000000000a"
		$lines | Should -Contain "shared github.com/myuser/dotfiles"
		$lines | Should -Contain "owns Work github.com/my-org/*"
		$lines | Should -Contain "autonomous github.com/myuser/myproject"
		$lines | Should -Not -Contain "autonomous github.com/my-org/never-listed"
	}

	It "reports a profile without a Plan and leaves forceLoginOrgUUID out" {
		$result = ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile (New-ActiveProfile @())

		@($result.Problems).Count | Should -Be 1
		($result.Settings | ConvertFrom-Json -AsHashtable).ContainsKey('forceLoginOrgUUID') | Should -BeFalse
	}

	It "renders nothing for a Plan that is configured but unusable, so the deployed copy keeps its pin" {
		$aiProfile = New-ActiveProfile @()
		$aiProfile.Profile.PlanErrors = @("AiProfiles.Profiles.Personal.Plan has an OrgUuid that is not a UUID => [a1d81f3-30fc]")

		$result = ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile

		$result.Settings | Should -BeNullOrEmpty -Because "a copy without forceLoginOrgUUID would let any Plan sign in"
		$result.ProfileConf | Should -BeNullOrEmpty
		@($result.Problems | Where-Object { $_ -like "*not a UUID*" }).Count | Should -Be 1
	}

	It "renders the same text every time, with LF line endings and a final newline" {
		$aiProfile = New-ActiveProfile @(@{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000a" })

		$first = (ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile).Settings
		$second = (ConvertTo-AiManagedSettings -Template $script:Template -ManagedDir "/etc/claude-code" -AiProfile $aiProfile).Settings

		$second | Should -BeExactly $first
		$first.Contains("`r") | Should -BeFalse
		$first.EndsWith("`n") | Should -BeTrue
	}

	It "returns no settings for a template that does not parse" {
		$result = ConvertTo-AiManagedSettings -Template "{ not json" -ManagedDir "/etc/claude-code"

		$result.Settings | Should -BeNullOrEmpty
		@($result.Problems).Count | Should -Be 1
	}
}
