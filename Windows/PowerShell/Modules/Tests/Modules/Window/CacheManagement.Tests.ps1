#Requires -Modules Pester

BeforeAll {
	# Clean module state without re-importing (and re-dot-sourcing) the whole module.
	. (Join-Path (Get-RepositoryPath).Modules "Tests\Modules\Support\Reset-WindowModuleState.ps1")
	Reset-WindowModuleState
}

Describe "Cache Management" {
	Context "Clear-WindowCache" {
		It "Should clear window cache without error" {
			{ Clear-WindowCache } | Should -Not -Throw
		}
	}

	Context "Clear-FancyZonesCache" {
		It "Should clear FancyZones cache without error" {
			{ Clear-FancyZonesCache } | Should -Not -Throw
		}
	}

	Context "Clear-MonitorCache" {
		It "Should clear monitor cache without error" {
			{ Clear-MonitorCache } | Should -Not -Throw
		}
	}

	Context "Set-WindowCacheMaxAge" {
		It "Should set cache max age without error" {
			{ Set-WindowCacheMaxAge -MaxAgeMs 100 } | Should -Not -Throw
		}

		It "Should accept different millisecond values" {
			{ Set-WindowCacheMaxAge -MaxAgeMs 0 } | Should -Not -Throw
			{ Set-WindowCacheMaxAge -MaxAgeMs 50 } | Should -Not -Throw
			{ Set-WindowCacheMaxAge -MaxAgeMs 5000 } | Should -Not -Throw
		}

		It "Should require MaxAgeMs parameter" {
			$cmd = Get-Command Set-WindowCacheMaxAge
			$param = $cmd.Parameters['MaxAgeMs']
			$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
			$mandatoryAttr.Mandatory | Should -BeTrue
		}
	}
}
