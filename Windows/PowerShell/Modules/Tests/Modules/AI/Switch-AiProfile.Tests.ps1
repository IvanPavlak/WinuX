#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiProfile.ps1"
	. "$FunctionsPath\Switch-AiProfile.ps1"
}

Describe "Switch-AiProfile" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }
		Mock Resolve-Selection { $null }
		Mock Test-AdminPrivileges { }
		Mock Deploy-AiArtifacts { }
		Mock Deploy-AiMcpServers { }
		Mock Deploy-AiMarketplaces { }
		Mock Test-AiProfile { $global:LASTEXITCODE = 0 }

		# The real Resolve-AiProfile, reading a synthetic configuration whose managed settings
		# folder is in the test drive; this host is in no Hosts entry, so it runs the default.
		$script:ManagedDir = Join-Path $TestDrive "managed"
		if (Test-Path -Path $script:ManagedDir) { Remove-Item -Path $script:ManagedDir -Recurse -Force }
		New-Item -ItemType Directory -Path $script:ManagedDir -Force | Out-Null
		$script:SwitchFile = Join-Path $script:ManagedDir "ai-profile.switch"
		$script:Harnesses = @{
			"my-harness" = @{
				Destinations = @(
					@{ Kind = "Rules"; Placement = "File"; Files = @("managed-settings.json"); Hooks = @("managed-settings"); Path = (Join-Path $script:ManagedDir "managed-settings.json") }
				)
			}
		}
		$script:Profiles = @{
			Hosts    = @{}
			Default  = "Personal"
			Profiles = @{
				Personal = @{ Rules = "MyRules" }
				Work     = @{ Rules = "MyWorkRules" }
			}
		}
		Mock Get-ConfigSetting {
			switch ($Path) {
				'AiProfiles' { $script:Profiles }
				'AiHarnesses' { $script:Harnesses }
				default { $null }
			}
		}

		$script:SavedOverride = $env:WINUX_AI_PROFILE
		$env:WINUX_AI_PROFILE = $null
	}

	AfterEach {
		$env:WINUX_AI_PROFILE = $script:SavedOverride
	}

	It "records the pick in the switch file, redeploys the rules only and checks the machine" {
		Switch-AiProfile work

		(Get-Content -Path $script:SwitchFile -Raw).Trim() | Should -Be "Work" -Because "the configured spelling is written, whatever case was typed"
		$resolved = Resolve-AiProfile
		$resolved.Name | Should -Be "Work"
		$resolved.Source | Should -Be "switched"
		Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly -ParameterFilter { @($Kind) -contains 'Rules' }
		Should -Invoke Deploy-AiMcpServers -Times 0
		Should -Invoke Deploy-AiMarketplaces -Times 0
		Should -Invoke Test-AiProfile -Times 1 -Exactly
	}

	It "redeploys every kind, the MCP servers and the marketplaces with -Full" {
		Switch-AiProfile Work -Full

		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly -ParameterFilter { -not $Kind }
		Should -Invoke Deploy-AiMcpServers -Times 1 -Exactly
		Should -Invoke Deploy-AiMarketplaces -Times 1 -Exactly
		Should -Invoke Test-AiProfile -Times 1 -Exactly
	}

	It "removes the switch file with -Reset, so the hostname or default pick returns, and redeploys" {
		Set-Content -Path $script:SwitchFile -Value "Work"

		Switch-AiProfile -Reset

		Test-Path -Path $script:SwitchFile | Should -BeFalse
		$resolved = Resolve-AiProfile
		$resolved.Name | Should -Be "Personal"
		$resolved.Source | Should -Be "default"
		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly -ParameterFilter { @($Kind) -contains 'Rules' }
	}

	It "refuses a name that is no configured profile, and a name together with -Reset, changing nothing" {
		Switch-AiProfile Nobody
		Switch-AiProfile Work -Reset

		Test-Path -Path $script:SwitchFile | Should -BeFalse
		Should -Invoke Deploy-AiArtifacts -Times 0
		Should -Invoke Test-AiProfile -Times 0
	}

	It "offers the configured profiles in a menu without a name, and changes nothing on Enter" {
		Set-Content -Path $script:SwitchFile -Value "Work"

		Switch-AiProfile

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter { (@($OptionList) -join ',') -eq 'Personal,Work,Reset' }
		(Get-Content -Path $script:SwitchFile -Raw).Trim() | Should -Be "Work"
		Should -Invoke Deploy-AiArtifacts -Times 0
	}

	It "switches to the profile picked in the menu, and offers no Reset while no switch is in effect" {
		Mock Resolve-Selection { "Work" }

		Switch-AiProfile

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter { (@($OptionList) -join ',') -eq 'Personal,Work' }
		(Get-Content -Path $script:SwitchFile -Raw).Trim() | Should -Be "Work"
		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly -ParameterFilter { @($Kind) -contains 'Rules' }
	}

	It "resets when Reset is picked in the menu" {
		Set-Content -Path $script:SwitchFile -Value "Work"
		Mock Resolve-Selection { "Reset" }

		Switch-AiProfile

		Test-Path -Path $script:SwitchFile | Should -BeFalse
		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly
	}

	It "takes profiles by whatever names the configuration gives them" {
		$script:Profiles.Profiles = @{ "Studio-A" = @{ Rules = "MyRules" }; "night_shift" = @{ Rules = "MyWorkRules" } }
		$script:Profiles.Default = "Studio-A"

		Switch-AiProfile NIGHT_SHIFT

		(Get-Content -Path $script:SwitchFile -Raw).Trim() | Should -Be "night_shift"
		(Resolve-AiProfile).Name | Should -Be "night_shift"
	}

	It "asks for the administrator rights before the menu, and writes nothing when they are refused" {
		Mock Test-AdminPrivileges { throw "Administrator privileges refused" }

		{ Switch-AiProfile Work } | Should -Throw
		{ Switch-AiProfile } | Should -Throw

		Should -Invoke Resolve-Selection -Times 0 -Because "a pick made before the elevated rerun would have to be made twice"

		Test-Path -Path $script:SwitchFile | Should -BeFalse
		Should -Invoke Deploy-AiArtifacts -Times 0
	}

	It "writes nothing under -WhatIf, asks for no rights, and previews the deploy as the picked profile" {
		$script:SeenOverride = $null
		Mock Deploy-AiArtifacts { $script:SeenOverride = $env:WINUX_AI_PROFILE }
		$env:WINUX_AI_PROFILE = "Personal"

		Switch-AiProfile Work -WhatIf

		Test-Path -Path $script:SwitchFile | Should -BeFalse
		Should -Invoke Test-AdminPrivileges -Times 0
		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters['WhatIf'] -and @($Kind) -contains 'Rules' }
		$script:SeenOverride | Should -Be "Work"
		$env:WINUX_AI_PROFILE | Should -Be "Personal" -Because "the preview puts the session's variable back"
		Should -Invoke Test-AiProfile -Times 0
	}

	It "deploys the profile it was given when WINUX_AI_PROFILE is set, and removes the variable from the session" {
		$script:SeenOverride = "unset"
		Mock Deploy-AiArtifacts { $script:SeenOverride = $env:WINUX_AI_PROFILE }
		$env:WINUX_AI_PROFILE = "Personal"

		Switch-AiProfile Work

		$script:SeenOverride | Should -BeNullOrEmpty
		$env:WINUX_AI_PROFILE | Should -BeNullOrEmpty
		(Resolve-AiProfile).Name | Should -Be "Work"
	}

	It "refuses to switch when no harness has a managed-settings destination" {
		$script:Harnesses = @{}

		Switch-AiProfile Work

		Should -Invoke Deploy-AiArtifacts -Times 0
	}

	It "does nothing when no profile is configured" {
		$script:Profiles = @{ Profiles = @{} }

		Switch-AiProfile Work

		Test-Path -Path $script:SwitchFile | Should -BeFalse
		Should -Invoke Deploy-AiArtifacts -Times 0
	}
}
