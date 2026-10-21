#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-PowerButtonActions.ps1"

	# reg.exe is called directly; stub it where it does not resolve so Mock can attach.
	if (-not (Get-Command reg -ErrorAction SilentlyContinue)) {
		function script:reg { }
	}

	$script:OriginalConfiguration = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Set-PowerButtonActions" {
	BeforeEach {
		Mock Test-AdminPrivileges { }
		Mock powercfg {
			if ($args[0] -eq "/list") {
				@("No power schemes available")
			}
		}
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
	}

	It "returns when no power schemes are found" {
		{ Set-PowerButtonActions -LidCloseOnBattery Sleep } | Should -Not -Throw

		Should -Invoke powercfg -Times 1 -ParameterFilter { $args[0] -eq "/list" }
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "changes nothing when no setting is given" {
		# Every omitted parameter used to take a hardcoded default, so a bare call disabled
		# Fast Startup, Sleep and Hibernate and rewrote all six button actions.
		Set-PowerButtonActions

		Should -Invoke powercfg -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "No power setting given" }
	}

	It "-Auto leaves power settings as-is when PowerButtonActions is empty (empty base, no hardcoded defaults)" {
		$global:Configuration = [PSCustomObject]@{ PowerButtonActions = @{} }
		Mock DetermineMachineType { "PC" }
		Mock Write-LogStep { }

		{ Set-PowerButtonActions -Auto } | Should -Not -Throw

		Should -Invoke powercfg -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "PowerButtonActions not configured" }
	}

	Context "applying" {
		BeforeEach {
			Mock powercfg {
				if ($args[0] -eq "/list") { @("Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *") }
				elseif ($args[0] -eq "/getactivescheme") { "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)" }
			}
			Mock reg { }
			Mock Test-Path { $false }
			Mock Get-ItemProperty { $null }
			Mock Write-LogSuccess { }
			Mock Write-LogStep { }
			Mock DetermineMachineType { "PC" }
		}

		It "changes only the action passed and leaves the toggles alone" {
			Set-PowerButtonActions -LidCloseOnBattery Sleep

			Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { $args -contains "/SETDCVALUEINDEX" -and $args -contains "LIDACTION" }
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args -contains "PBUTTONACTION" -or $args -contains "SBUTTONACTION" }
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args -contains "/SETACVALUEINDEX" }
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args[0] -eq "/hibernate" }
			Should -Invoke reg -Times 0 -ParameterFilter { ($args -join ' ') -match "HiberbootEnabled|ShowSleepOption|ShowHibernateOption" }
		}

		It "-Auto leaves Sleep and Hibernate alone when the entry leaves them out" {
			# A missing DisableSleep / DisableHibernate used to be applied as $false, turning
			# hibernation on and showing Sleep.
			$global:Configuration = [PSCustomObject]@{ PowerButtonActions = @{ PC = @{ PowerButtonOnBattery = "ShutDown" } } }

			Set-PowerButtonActions -Auto

			Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { $args -contains "PBUTTONACTION" }
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args[0] -eq "/hibernate" }
			Should -Invoke reg -Times 0 -ParameterFilter { ($args -join ' ') -match "ShowSleepOption|ShowHibernateOption|HiberbootEnabled" }
		}

		It "-Auto applies the toggles the entry sets" {
			$global:Configuration = [PSCustomObject]@{ PowerButtonActions = @{ PC = @{ DisableHibernate = $true; DisableSleep = $false } } }

			Set-PowerButtonActions -Auto

			Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { $args[0] -eq "/hibernate" -and $args[1] -eq "off" }
			Should -Invoke reg -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -match "ShowSleepOption" -and ($args -join ' ') -match "/d 1" }
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args -contains "LIDACTION" }
		}

		It "-Auto lets an explicit parameter override the entry" {
			$global:Configuration = [PSCustomObject]@{ PowerButtonActions = @{ PC = @{ LidCloseOnBattery = "ShutDown" } } }

			Set-PowerButtonActions -Auto -LidCloseOnBattery Hibernate

			# Hibernate is powercfg action index 2.
			Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { $args -contains "LIDACTION" -and $args[-1] -eq 2 }
		}
	}
}
