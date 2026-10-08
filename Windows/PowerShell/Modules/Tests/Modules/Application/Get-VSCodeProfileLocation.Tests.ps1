#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Get-VSCodeProfileLocation.ps1"
}

Describe "Get-VSCodeProfileLocation" {
	BeforeEach {
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }
		Mock Backup-RepositoryItem { "C:\Backups\storage" }
		Mock Get-Process { $null } -ParameterFilter { $Name -eq "Code" }

		$script:UserData = Join-Path $TestDrive "User"
		$script:Storage = Join-Path $script:UserData "globalStorage\storage.json"
		Remove-Item -Path $script:UserData -Recurse -Force -ErrorAction SilentlyContinue
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Storage) -Force | Out-Null
		Set-Content -Path $script:Storage -Value '{"theme":"vs-dark","userDataProfiles":[{"location":"-3f2a","name":"Writing"}]}'
	}

	It "returns the user data folder for the Default profile" {
		Get-VSCodeProfileLocation -Name "Default" -UserData $script:UserData | Should -Be $script:UserData
	}

	It "returns the folder of a registered profile, matching its name case-insensitively" {
		Get-VSCodeProfileLocation -Name "writing" -UserData $script:UserData | Should -Be (Join-Path $script:UserData "profiles\-3f2a")
	}

	It "returns nothing for an unregistered profile without -Register, leaving the profile list alone" {
		$before = Get-Content -Path $script:Storage -Raw

		Get-VSCodeProfileLocation -Name "Work" -UserData $script:UserData | Should -BeNullOrEmpty
		Get-Content -Path $script:Storage -Raw | Should -Be $before
	}

	It "registers an unknown profile, keeping every other key, and creates its folder" {
		$folder = Get-VSCodeProfileLocation -Name "My Work" -UserData $script:UserData -Register

		$folder | Should -Be (Join-Path $script:UserData "profiles\winux-my-work")
		Test-Path -Path $folder -PathType Container | Should -BeTrue
		$state = Get-Content -Path $script:Storage -Raw | ConvertFrom-Json
		$state.theme | Should -Be "vs-dark"
		@($state.userDataProfiles).Count | Should -Be 2
		$state.userDataProfiles[1].name | Should -Be "My Work"
		$state.userDataProfiles[1].location | Should -Be "winux-my-work"
		Should -Invoke Backup-RepositoryItem -Times 1 -Exactly -ParameterFilter { $Category -eq "VSCodeProfiles" }
	}

	It "finds the profile it registered on the next run instead of registering it again" {
		Get-VSCodeProfileLocation -Name "Work" -UserData $script:UserData -Register | Out-Null
		Get-VSCodeProfileLocation -Name "Work" -UserData $script:UserData -Register | Out-Null

		@((Get-Content -Path $script:Storage -Raw | ConvertFrom-Json).userDataProfiles).Count | Should -Be 2
	}

	It "refuses to register while VS Code is running" {
		Mock Get-Process { [pscustomobject]@{ Name = "Code" } } -ParameterFilter { $Name -eq "Code" }
		$before = Get-Content -Path $script:Storage -Raw

		Get-VSCodeProfileLocation -Name "Work" -UserData $script:UserData -Register | Should -BeNullOrEmpty
		Get-Content -Path $script:Storage -Raw | Should -Be $before
		Should -Invoke Write-LogError -Times 1 -Exactly
	}

	It "creates the profile list when VS Code has never started" {
		Remove-Item -Path $script:Storage -Force

		Get-VSCodeProfileLocation -Name "Work" -UserData $script:UserData -Register | Should -Be (Join-Path $script:UserData "profiles\winux-work")
		(Get-Content -Path $script:Storage -Raw | ConvertFrom-Json).userDataProfiles[0].name | Should -Be "Work"
		Should -Invoke Backup-RepositoryItem -Times 0
	}

	It "returns nothing when the profile list cannot be read" {
		Set-Content -Path $script:Storage -Value "{ not json"

		Get-VSCodeProfileLocation -Name "Work" -UserData $script:UserData -Register | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 1 -Exactly
	}
}
