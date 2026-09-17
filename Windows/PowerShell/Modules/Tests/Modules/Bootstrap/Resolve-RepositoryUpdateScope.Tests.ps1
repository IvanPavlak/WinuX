#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Bootstrap\Functions\Resolve-RepositoryUpdateScope.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-RepositoryUpdateScope" {
	BeforeEach {
		$global:Configuration = @{ BootstrapConfig = @{} }
		$global:MachineType = "Test"
	}

	It "Should fall back to All when RepositoryUpdateScope is absent" {
		$scope = Resolve-RepositoryUpdateScope

		$scope.All | Should -BeTrue
		$scope.Groups | Should -BeNullOrEmpty
	}

	It "Should treat All case-insensitively" {
		$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = "all" }

		(Resolve-RepositoryUpdateScope).All | Should -BeTrue
	}

	It "Should prefer the machine type's value over Default" {
		$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = "All"; Test = "Private" }

		$scope = Resolve-RepositoryUpdateScope

		$scope.All | Should -BeFalse
		$scope.Groups -join "," | Should -Be "Private"
	}

	It "Should fall back to Default for a machine type that is not listed" {
		$global:MachineType = "Laptop"
		$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = "Work"; Test = "Private" }

		(Resolve-RepositoryUpdateScope).Groups -join "," | Should -Be "Work"
	}

	It "Should split a comma-separated string into groups, trimmed and in order" {
		$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Test = "Work,  Private ,OpenSource" }

		$scope = Resolve-RepositoryUpdateScope

		$scope.All | Should -BeFalse
		$scope.Groups -join "," | Should -Be "Work,Private,OpenSource"
	}

	It "Should accept an array of group names" {
		$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Test = @("Work", "Private") }

		(Resolve-RepositoryUpdateScope).Groups -join "," | Should -Be "Work,Private"
	}

	It "Should not treat a group named alongside All as All" {
		# "All" only means every repository when it stands alone; a fork is free to define a
		# group whose name happens to be All and list it with others.
		$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Test = "All, Work" }

		$scope = Resolve-RepositoryUpdateScope

		$scope.All | Should -BeFalse
		$scope.Groups -join "," | Should -Be "All,Work"
	}

	It "Should fall back to All when the configured value names nothing" {
		$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = " , " }

		(Resolve-RepositoryUpdateScope).All | Should -BeTrue
	}
}
