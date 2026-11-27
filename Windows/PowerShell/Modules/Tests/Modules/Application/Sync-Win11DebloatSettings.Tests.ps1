#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$script:OriginalLocalAppData = $env:LOCALAPPDATA

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Sync-Win11DebloatSettings.ps1"

	$script:SettingsJson = '{ "Version": "1.0", "Settings": [] }'
}

AfterAll {
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
	$env:LOCALAPPDATA = $script:OriginalLocalAppData
}

Describe "Sync-Win11DebloatSettings" {
	BeforeEach {
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		# Creating a symbolic link needs elevation or Developer Mode, so the link itself is mocked;
		# every other New-Item call (directories) runs for real inside TestDrive.
		Mock New-Item { } -ParameterFilter { $ItemType -eq 'SymbolicLink' }

		$caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
		$script:RepoRoot = Join-Path $caseRoot 'Repo'
		$script:RepositorySettingsPath = Join-Path $script:RepoRoot 'Windows\Win11Debloat\LastUsedSettings.json'
		$script:UserDataPath = Join-Path $caseRoot 'LocalAppData\Win11Debloat'
		$script:UserSettingsPath = Join-Path $script:UserDataPath 'LastUsedSettings.json'

		[System.IO.Directory]::CreateDirectory((Split-Path -Path $script:RepositorySettingsPath -Parent)) | Out-Null
		[System.IO.Directory]::CreateDirectory($script:UserDataPath) | Out-Null

		$env:LOCALAPPDATA = Join-Path $caseRoot 'LocalAppData'
		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = $script:RepoRoot } }
		}
	}

	AfterEach {
		$env:LOCALAPPDATA = $script:OriginalLocalAppData
	}

	It "links the user data settings file to the repository file when the repository has settings" {
		Set-Content -LiteralPath $script:RepositorySettingsPath -Value $script:SettingsJson

		Sync-Win11DebloatSettings | Should -BeTrue

		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
			$ItemType -eq 'SymbolicLink' -and $Path -eq $script:UserSettingsPath -and $Target -eq $script:RepositorySettingsPath
		}
	}

	It "creates the user data folder before linking when it does not exist yet" {
		Set-Content -LiteralPath $script:RepositorySettingsPath -Value $script:SettingsJson
		Remove-Item -LiteralPath $script:UserDataPath -Recurse -Force

		Sync-Win11DebloatSettings | Should -BeTrue

		Test-Path -LiteralPath $script:UserDataPath | Should -BeTrue
	}

	It "makes no link and returns false when neither side has settings" {
		Sync-Win11DebloatSettings | Should -BeFalse

		Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "makes no link when the repository file is blank" {
		Set-Content -LiteralPath $script:RepositorySettingsPath -Value '   '

		Sync-Win11DebloatSettings | Should -BeFalse

		Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "adopts settings saved outside the repository when the repository file is missing" {
		Set-Content -LiteralPath $script:UserSettingsPath -Value $script:SettingsJson

		Sync-Win11DebloatSettings | Should -BeTrue

		(Get-Content -LiteralPath $script:RepositorySettingsPath -Raw).Trim() | Should -Be $script:SettingsJson
		Test-Path -LiteralPath $script:UserSettingsPath | Should -BeFalse -Because "the real file makes way for the link"
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -like 'Adopted the saved Win11Debloat settings*' }
	}

	It "keeps the repository file and sets the saved file aside when both have settings" {
		$savedOutside = '{ "Version": "1.0", "Settings": [ { "Name": "RemoveApps", "Value": true } ] }'
		Set-Content -LiteralPath $script:RepositorySettingsPath -Value $script:SettingsJson
		Set-Content -LiteralPath $script:UserSettingsPath -Value $savedOutside

		Sync-Win11DebloatSettings | Should -BeTrue

		$unlinkedSettingsPath = Join-Path $script:UserDataPath 'LastUsedSettings.unlinked.json'
		(Get-Content -LiteralPath $script:RepositorySettingsPath -Raw).Trim() | Should -Be $script:SettingsJson
		(Get-Content -LiteralPath $unlinkedSettingsPath -Raw).Trim() | Should -Be $savedOutside
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -eq "Win11Debloat settings saved outside the repo were kept at: $unlinkedSettingsPath" }
	}

	It "removes a blank saved file and links when the repository has settings" {
		Set-Content -LiteralPath $script:RepositorySettingsPath -Value $script:SettingsJson
		Set-Content -LiteralPath $script:UserSettingsPath -Value ''

		Sync-Win11DebloatSettings | Should -BeTrue

		Test-Path -LiteralPath (Join-Path $script:UserDataPath 'LastUsedSettings.unlinked.json') | Should -BeFalse
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "leaves an existing link to the repository file alone" {
		Set-Content -LiteralPath $script:RepositorySettingsPath -Value $script:SettingsJson
		Mock Get-Item {
			[PSCustomObject]@{ LinkType = 'SymbolicLink'; Target = @($script:RepositorySettingsPath) }
		}

		Sync-Win11DebloatSettings | Should -BeTrue

		Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "replaces a link that points somewhere else" {
		Set-Content -LiteralPath $script:RepositorySettingsPath -Value $script:SettingsJson
		Mock Get-Item {
			[PSCustomObject]@{ LinkType = 'SymbolicLink'; Target = @('C:\Elsewhere\LastUsedSettings.json') }
		}

		Sync-Win11DebloatSettings | Should -BeTrue

		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' -and $Target -eq $script:RepositorySettingsPath }
	}
}
