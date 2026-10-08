#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Deploy-VSCodeProfiles.ps1"
	# The helpers run for real so these tests exercise the whole deploy against a fake profile.
	. "$FunctionsPath\Resolve-VSCodeProfilesConfig.ps1"
	. "$FunctionsPath\Get-VSCodeProfileItems.ps1"
	. "$FunctionsPath\Get-VSCodeProfileLocation.ps1"
	. "$FunctionsPath\Get-VSCodeInstalledExtensions.ps1"
	. "$FunctionsPath\ConvertFrom-VSCodeExtensionLine.ps1"
	. "$FunctionsPath\Get-VSCodeCliPath.ps1"
	# The cmdlet itself, captured before any mock shadows it.
	$script:RealGetItem = Get-Command -Name Get-Item -CommandType Cmdlet
}

Describe "Deploy-VSCodeProfiles" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }
		Mock New-WindowsSymbolicLink { }
		Mock Backup-RepositoryItem { "C:\Backups\storage" }
		Mock Get-Process { $null } -ParameterFilter { $Name -eq "Code" }

		$script:Root = Join-Path $TestDrive "repo\Profiles"
		$script:UserData = Join-Path $TestDrive "User"
		Remove-Item -Path (Join-Path $TestDrive "repo"), $script:UserData -Recurse -Force -ErrorAction SilentlyContinue
		$script:Source = Join-Path $script:Root "MyProfile"
		New-Item -ItemType Directory -Path $script:Source -Force | Out-Null
		New-Item -ItemType Directory -Path (Join-Path $script:UserData "globalStorage") -Force | Out-Null
		Set-Content -Path (Join-Path $script:Source "settings.json") -Value "{}"
		Set-Content -Path (Join-Path $script:Source "extensions.txt") -Value @("# tools", "a.wanted", "b.present", "c.pinned@2.0.0")

		$script:Section = @{
			Root         = $script:Root
			UserData     = $script:UserData
			SettingsSync = $false
			Prune        = $false
			Catalogue    = @(@{ MyProfile = @{ Target = "Default" } })
			Deploy       = @{ Default = @("MyProfile") }
		}
		Mock Get-ConfigSetting { $script:Section } -ParameterFilter { $Path -eq 'VSCodeProfiles' }

		# A stand-in CLI: records every call; the listing answers what the test set.
		$script:Log = Join-Path $TestDrive "calls.log"
		if (Test-Path -Path $script:Log) { Remove-Item -Path $script:Log -Force }
		$env:WINUX_TEST_CODE_LIST = "B.Present@1.0.0;c.pinned@1.0.0;d.extra@3.0.0"
		$script:Stub = Join-Path $TestDrive "code-stub.ps1"
		Set-Content -Path $script:Stub -Value @(
			"Add-Content -Path '$script:Log' -Value (`$args -join ' ')",
			"if (`$args[0] -eq '--list-extensions') { `$env:WINUX_TEST_CODE_LIST -split ';' | Where-Object { `$_ }; exit 0 }",
			"if ((`$args -join ' ') -like '*broken*') { exit 1 }",
			"exit 0"
		)
	}

	AfterEach {
		Remove-Item -Path Env:\WINUX_TEST_CODE_LIST -ErrorAction SilentlyContinue
	}

	It "does nothing when this machine type selects no profile" {
		$script:Section.Deploy = @{ Default = @() }

		Deploy-VSCodeProfiles -Command $script:Stub

		Should -Invoke New-WindowsSymbolicLink -Times 0
		Test-Path -Path $script:Log | Should -BeFalse
	}

	It "links the files the profile folder carries into the Default profile" {
		Deploy-VSCodeProfiles -Command $script:Stub

		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly -ParameterFilter {
			$Path -eq (Join-Path $script:UserData "settings.json") -and $Target -eq (Join-Path $script:Source "settings.json")
		}
	}

	It "leaves a link that already points at the repository file alone" {
		$live = Join-Path $script:UserData "settings.json"
		$repo = Join-Path $script:Source "settings.json"
		Mock Get-Item { if ($LiteralPath) { & $script:RealGetItem -LiteralPath $LiteralPath -Force:$Force -ErrorAction SilentlyContinue } else { & $script:RealGetItem -Path $Path -Force:$Force -ErrorAction SilentlyContinue } }
		Mock Get-Item { [pscustomobject]@{ LinkType = "SymbolicLink"; Target = @($repo) } } -ParameterFilter { $LiteralPath -eq $live }

		Deploy-VSCodeProfiles -Command $script:Stub

		Should -Invoke New-WindowsSymbolicLink -Times 0
	}

	It "installs only the listed extensions the profile lacks, with --do-not-sync when Settings Sync is off" {
		Deploy-VSCodeProfiles -Command $script:Stub

		$calls = @(Get-Content -Path $script:Log)
		$calls | Should -Contain "--install-extension a.wanted --do-not-sync"
		$calls | Where-Object { $_ -like "*b.present*" } | Should -BeNullOrEmpty
	}

	It "reinstalls a pinned extension installed at another version" {
		Deploy-VSCodeProfiles -Command $script:Stub

		@(Get-Content -Path $script:Log) | Should -Contain "--install-extension c.pinned@2.0.0 --do-not-sync --force"
	}

	It "installs without --do-not-sync when Settings Sync is on" {
		$script:Section.SettingsSync = $true

		Deploy-VSCodeProfiles -Command $script:Stub

		@(Get-Content -Path $script:Log) | Should -Contain "--install-extension a.wanted"
	}

	It "leaves unlisted extensions installed by default" {
		Deploy-VSCodeProfiles -Command $script:Stub

		@(Get-Content -Path $script:Log) | Where-Object { $_ -like "--uninstall-extension*" } | Should -BeNullOrEmpty
	}

	It "uninstalls unlisted extensions with -Prune" {
		Deploy-VSCodeProfiles -Command $script:Stub -Prune

		$uninstalls = @(Get-Content -Path $script:Log | Where-Object { $_ -like "--uninstall-extension*" })
		$uninstalls | Should -Be @("--uninstall-extension d.extra")
	}

	It "uninstalls unlisted extensions when VSCodeProfiles.Prune is set" {
		$script:Section.Prune = $true

		Deploy-VSCodeProfiles -Command $script:Stub

		@(Get-Content -Path $script:Log) | Should -Contain "--uninstall-extension d.extra"
	}

	It "registers a named profile and addresses it with --profile" {
		$script:Section.Catalogue = @(@{ MyProfile = @{ Target = "Writing" } })

		Deploy-VSCodeProfiles -Command $script:Stub

		$folder = Join-Path $script:UserData "profiles\winux-writing"
		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $folder "settings.json") }
		@(Get-Content -Path $script:Log) | Should -Contain "--install-extension a.wanted --profile Writing --do-not-sync"
		(Get-Content -Path (Join-Path $script:UserData "globalStorage\storage.json") -Raw | ConvertFrom-Json).userDataProfiles[0].name | Should -Be "Writing"
	}

	It "skips a named profile it cannot register while VS Code is running" {
		$script:Section.Catalogue = @(@{ MyProfile = @{ Target = "Writing" } })
		Mock Get-Process { [pscustomobject]@{ Name = "Code" } } -ParameterFilter { $Name -eq "Code" }

		Deploy-VSCodeProfiles -Command $script:Stub

		Should -Invoke New-WindowsSymbolicLink -Times 0
		Test-Path -Path $script:Log | Should -BeFalse
	}

	It "reports a selected name the catalogue does not carry and deploys the rest" {
		$script:Section.Deploy = @{ Default = @("Missing", "MyProfile") }

		Deploy-VSCodeProfiles -Command $script:Stub

		Should -Invoke Write-LogError -ParameterFilter { $Message -like "*Missing*Catalogue*" }
		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly
	}

	It "skips a catalogue entry whose folder does not exist yet" {
		Remove-Item -Path $script:Source -Recurse -Force

		Deploy-VSCodeProfiles -Command $script:Stub

		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "*MyProfile*no folder*" }
		Should -Invoke New-WindowsSymbolicLink -Times 0
	}

	It "still links the files when VS Code's command line is missing" {
		Mock Get-VSCodeCliPath { $null }

		Deploy-VSCodeProfiles

		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "*command line*not found*" }
	}

	It "deploys the entries -Name gives instead of the machine type's list" {
		$script:Section.Deploy = @{ Default = @() }

		Deploy-VSCodeProfiles -Name MyProfile -Command $script:Stub

		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly
	}

	It "reports a failed install and carries on" {
		Set-Content -Path (Join-Path $script:Source "extensions.txt") -Value @("x.broken", "a.wanted")

		Deploy-VSCodeProfiles -Command $script:Stub

		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like "*x.broken*failed*" }
		@(Get-Content -Path $script:Log) | Should -Contain "--install-extension a.wanted --do-not-sync"
	}
}
