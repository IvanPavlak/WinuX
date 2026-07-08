#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-VirtualDesktopGuid.ps1"

	$script:Guid0 = [System.Guid]::new("aaaaaaaa-1111-2222-3333-444444444444")
	$script:Guid1 = [System.Guid]::new("bbbbbbbb-5555-6666-7777-888888888888")
	$script:TwoDesktopBytes = @($script:Guid0.ToByteArray()) + @($script:Guid1.ToByteArray())
}

Describe "Get-VirtualDesktopGuid" {
	It "returns the braced upper-case GUID for the first desktop" {
		Mock Get-ItemProperty { [PSCustomObject]@{ VirtualDesktopIDs = $script:TwoDesktopBytes } }

		$result = Get-VirtualDesktopGuid -DesktopIndex 0

		$result | Should -Be "{$($script:Guid0.ToString().ToUpper())}"
	}

	It "returns the GUID for a later desktop index" {
		Mock Get-ItemProperty { [PSCustomObject]@{ VirtualDesktopIDs = $script:TwoDesktopBytes } }

		$result = Get-VirtualDesktopGuid -DesktopIndex 1

		$result | Should -Be "{$($script:Guid1.ToString().ToUpper())}"
	}

	It "returns null when the index is out of range" {
		Mock Get-ItemProperty { [PSCustomObject]@{ VirtualDesktopIDs = $script:TwoDesktopBytes } }

		Get-VirtualDesktopGuid -DesktopIndex 5 | Should -BeNullOrEmpty
	}

	It "returns null when the registry value is missing" {
		Mock Get-ItemProperty { throw "registry value not found" }

		Get-VirtualDesktopGuid -DesktopIndex 0 | Should -BeNullOrEmpty
	}

	It "returns null when the registry value is empty" {
		Mock Get-ItemProperty { [PSCustomObject]@{ VirtualDesktopIDs = @() } }

		Get-VirtualDesktopGuid -DesktopIndex 0 | Should -BeNullOrEmpty
	}
}
