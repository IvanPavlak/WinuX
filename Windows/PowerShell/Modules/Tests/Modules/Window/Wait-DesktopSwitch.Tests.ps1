#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Wait-DesktopSwitch.ps1"
}

Describe "Wait-DesktopSwitch" {
	BeforeEach {
		# Stub VirtualDesktop cmdlets so the helper can be exercised without the module.
		function Get-Desktop { }
		function Get-DesktopIndex { param($Desktop) }
	}

	It "returns true immediately when the target desktop is already active" {
		Mock Get-Desktop { "desktop-obj" }
		Mock Get-DesktopIndex { 2 }

		$result = Wait-DesktopSwitch -TargetDesktopIndex 2 -PollIntervalMs 0

		$result | Should -BeTrue
		Should -Invoke Get-DesktopIndex -Times 1
	}

	It "returns true once the desktop index converges to the target" {
		$script:pollCount = 0
		Mock Get-Desktop { "desktop-obj" }
		Mock Get-DesktopIndex {
			$script:pollCount++
			if ($script:pollCount -ge 3) { 1 } else { 0 }
		}

		$result = Wait-DesktopSwitch -TargetDesktopIndex 1 -TimeoutMs 5000 -PollIntervalMs 0

		$result | Should -BeTrue
		$script:pollCount | Should -BeGreaterOrEqual 3
	}

	It "returns false when the target desktop is never reached before timeout" {
		Mock Get-Desktop { "desktop-obj" }
		Mock Get-DesktopIndex { 0 }

		$result = Wait-DesktopSwitch -TargetDesktopIndex 9 -TimeoutMs 30 -PollIntervalMs 0

		$result | Should -BeFalse
	}

	It "keeps polling through transient errors instead of throwing" {
		$script:pollCount = 0
		Mock Get-Desktop { "desktop-obj" }
		Mock Get-DesktopIndex {
			$script:pollCount++
			if ($script:pollCount -lt 2) { throw "RPC unavailable" }
			3
		}

		$result = Wait-DesktopSwitch -TargetDesktopIndex 3 -TimeoutMs 5000 -PollIntervalMs 0

		$result | Should -BeTrue
	}
}
