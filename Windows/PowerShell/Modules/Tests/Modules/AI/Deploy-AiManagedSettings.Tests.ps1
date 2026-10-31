#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Deploy-AiManagedSettings.ps1"
	# The renderer runs for real, so the written files are what a deploy writes.
	. "$FunctionsPath\ConvertTo-AiManagedSettings.ps1"
}

Describe "Deploy-AiManagedSettings" {
	BeforeEach {
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Backup-RepositoryItem { Join-Path $TestDrive "backup" }

		foreach ($stale in @("rules", "managed", "guard")) {
			$path = Join-Path $TestDrive $stale
			if (Test-Path -Path $path) { Remove-Item -Path $path -Recurse -Force }
		}
		$script:Rules = Join-Path $TestDrive "rules\MyRules"
		New-Item -ItemType Directory -Path (Join-Path $script:Rules "hooks") -Force | Out-Null
		Set-Content -Path (Join-Path $script:Rules "managed-settings.json") -Value '{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"{ManagedDir}/hooks/policy.sh\"" } ] } ] } }'
		[IO.File]::WriteAllText((Join-Path $script:Rules "hooks\policy.sh"), "#!/usr/bin/env bash`r`nexit 0`r`n")
		$script:Guard = Join-Path $TestDrive "guard\ai-ownership-guard.sh"
		New-Item -ItemType Directory -Path (Split-Path $script:Guard) -Force | Out-Null
		[IO.File]::WriteAllText($script:Guard, "#!/usr/bin/env bash`nexit 0`n")

		$script:Managed = Join-Path $TestDrive "managed"
		$script:Target = Join-Path $script:Managed "managed-settings.json"
		$script:Destination = @{
			Harness = "claude-code"; Kind = "rules"; Placement = "file"; Hooks = @("managed-settings")
			Path = $script:Target; WSLPath = "/etc/claude-code/managed-settings.json"
			Items = @(@{ Kind = "rules"; Name = "MyRules"; Source = (Join-Path $script:Rules "managed-settings.json"); Target = $script:Target; WSLTarget = "/etc/claude-code/managed-settings.json" })
		}
		$selected = @{ Name = "Personal"; Plans = @(@{ Name = "Max"; OrgUuid = "00000000-0000-0000-0000-00000000000a" }); Unattended = $true; Autonomous = @(); Owns = @() }
		$script:AiProfile = @{ Enabled = $true; Name = "Personal"; Profile = $selected; Profiles = [ordered]@{ Personal = $selected }; Shared = @(); DefaultOwner = "Personal" }

		$script:WSLCalls = @()
		Mock wsl {
			$script:WSLCalls += , @($args)
			$global:LASTEXITCODE = 0
		}
	}

	It "writes the rendered copy, the hooks, the guard and ai-profile.conf, never a link" {
		$result = Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard

		$result.Failures | Should -Be 0
		(Get-Item -LiteralPath $script:Target).Attributes -band [IO.FileAttributes]::ReparsePoint | Should -Be 0
		$settings = Get-Content -LiteralPath $script:Target -Raw | ConvertFrom-Json -AsHashtable
		$settings.forceLoginOrgUUID | Should -Be "00000000-0000-0000-0000-00000000000a"
		$settings.hooks.PreToolUse[0].hooks[0].command | Should -BeLike "*$($script:Managed.Replace('\', '/'))/hooks/policy.sh*"
		[IO.File]::ReadAllText((Join-Path $script:Managed "hooks\policy.sh")) | Should -BeExactly "#!/usr/bin/env bash`nexit 0`n" -Because "a hook script is deployed with LF line endings"
		Test-Path -LiteralPath (Join-Path $script:Managed "ai-ownership-guard.sh") | Should -BeTrue
		Get-Content -LiteralPath (Join-Path $script:Managed "ai-profile.conf") | Should -Contain "profile Personal"
	}

	It "leaves the deployed copy and its pin untouched when the profile's Plan is configured but unusable" {
		Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard | Out-Null
		$before = [IO.File]::ReadAllText($script:Target)
		$script:AiProfile.Profile.Plans = @()
		$script:AiProfile.Profile.PlanErrors = @("AiProfiles.Profiles.Personal.Plan has an OrgUuid that is not a UUID => [a1d81f3-30fc]")
		$script:WSLCalls = @()

		$result = Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard -Distribution "Ubuntu"

		$result.Failures | Should -BeGreaterThan 0
		[IO.File]::ReadAllText($script:Target) | Should -BeExactly $before
		(Get-Content -LiteralPath $script:Target -Raw | ConvertFrom-Json -AsHashtable).forceLoginOrgUUID | Should -Be "00000000-0000-0000-0000-00000000000a"
		$script:WSLCalls.Count | Should -Be 0 -Because "the WSL copy is not rewritten either"
	}

	It "writes neither the guard nor ai-profile.conf with profiles off" {
		Deploy-AiManagedSettings -Destination $script:Destination -AiProfile @{ Enabled = $false } -GuardPath $script:Guard | Out-Null

		Test-Path -LiteralPath $script:Target | Should -BeTrue
		Test-Path -LiteralPath (Join-Path $script:Managed "ai-ownership-guard.sh") | Should -BeFalse
		Test-Path -LiteralPath (Join-Path $script:Managed "ai-profile.conf") | Should -BeFalse
	}

	It "rewrites nothing when the deployed copy already matches" {
		Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard | Out-Null
		$before = (Get-Item -LiteralPath $script:Target).LastWriteTimeUtc
		Start-Sleep -Milliseconds 20

		Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard | Out-Null

		(Get-Item -LiteralPath $script:Target).LastWriteTimeUtc | Should -Be $before
		Should -Invoke Backup-RepositoryItem -Times 0
	}

	It "backs up a real file that differs before replacing it" {
		New-Item -ItemType Directory -Path $script:Managed -Force | Out-Null
		Set-Content -Path $script:Target -Value '{ "edited": true }'

		Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard | Out-Null

		Should -Invoke Backup-RepositoryItem -Times 1 -Exactly -ParameterFilter { $Path -eq $script:Target }
		(Get-Content -LiteralPath $script:Target -Raw | ConvertFrom-Json -AsHashtable).ContainsKey('edited') | Should -BeFalse
	}

	It "changes nothing under -WhatIf and reports every missing file as a failure" {
		$result = Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard -Distribution "Ubuntu" -WhatIf

		Test-Path -LiteralPath $script:Managed | Should -BeFalse
		$result.Failures | Should -Be 4
		Should -Invoke wsl -Times 0
	}

	It "copies the WSL twin as root in one wsl call, and removes its staging files" {
		Mock Get-RepositoryPath { @{ Repo = (Join-Path $TestDrive "Repo") } }

		$result = Deploy-AiManagedSettings -Destination $script:Destination -AiProfile $script:AiProfile -GuardPath $script:Guard -Distribution "Ubuntu"

		$result.Failures | Should -Be 0
		$script:WSLCalls.Count | Should -Be 1
		($script:WSLCalls[0] -join ' ') | Should -BeLike "-d Ubuntu -u root -e sh /mnt/*/winux-ai-managed-*.sh"
		$wslScript = [string]$script:WSLCalls[0][-1]
		Test-Path -LiteralPath ($wslScript.Substring(5, 1) + ":" + $wslScript.Substring(6).Replace('/', '\')) | Should -BeFalse
	}
}
