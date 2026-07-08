#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Test-FancyZonesLayoutApplied.ps1"

	# Get-AppliedFancyZonesState is a sibling helper; stub it so it can be mocked per-test.
	function Get-AppliedFancyZonesState { }

	$script:Guid = "{CF6C2856-0D59-466D-AA7F-E6DF85C6034C}"
}

Describe "Test-FancyZonesLayoutApplied" {
	It "returns false when the applied state cannot be read" {
		Mock Get-AppliedFancyZonesState { $null }

		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $script:Guid | Should -BeFalse
	}

	It "returns false when the applied state is empty" {
		Mock Get-AppliedFancyZonesState { @{} }

		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $script:Guid | Should -BeFalse
	}

	It "returns true when any monitor has a layout applied on the desktop" {
		Mock Get-AppliedFancyZonesState { @{ "LEN8ABC:$($script:Guid)" = "{LAYOUT-UUID}" } }

		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $script:Guid | Should -BeTrue
	}

	It "returns false when no entry matches the desktop GUID" {
		Mock Get-AppliedFancyZonesState { @{ "LEN8ABC:{00000000-0000-0000-0000-000000000000}" = "{LAYOUT-UUID}" } }

		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $script:Guid | Should -BeFalse
	}

	It "matches a specific monitor when MonitorId is provided" {
		Mock Get-AppliedFancyZonesState { @{ "LEN8ABC:$($script:Guid)" = "{LAYOUT-UUID}" } }

		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $script:Guid -MonitorId "LEN8ABC" | Should -BeTrue
		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $script:Guid -MonitorId "DELA1A8" | Should -BeFalse
	}

	It "normalizes a GUID supplied without braces or upper-casing" {
		Mock Get-AppliedFancyZonesState { @{ "LEN8ABC:$($script:Guid)" = "{LAYOUT-UUID}" } }

		$bareGuid = $script:Guid.Trim('{', '}').ToLower()
		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $bareGuid | Should -BeTrue
	}
}
