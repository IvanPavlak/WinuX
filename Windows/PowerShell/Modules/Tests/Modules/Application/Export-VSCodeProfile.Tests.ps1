#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Export-VSCodeProfile.ps1"
	# The helpers run for real so these tests exercise the whole capture against a fake profile.
	. "$FunctionsPath\Resolve-VSCodeProfilesConfig.ps1"
	. "$FunctionsPath\Get-VSCodeProfileItems.ps1"
	. "$FunctionsPath\Get-VSCodeProfileLocation.ps1"
	. "$FunctionsPath\Get-VSCodeInstalledExtensions.ps1"
	. "$FunctionsPath\ConvertFrom-VSCodeExtensionLine.ps1"
	. "$FunctionsPath\Merge-VSCodeExtensionList.ps1"
	. "$FunctionsPath\Get-VSCodeCliPath.ps1"
	# The cmdlet itself, captured before any mock shadows it.
	$script:RealGetItem = Get-Command -Name Get-Item -CommandType Cmdlet
}

Describe "Export-VSCodeProfile" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }

		$script:Root = Join-Path $TestDrive "repo\Profiles"
		$script:UserData = Join-Path $TestDrive "User"
		Remove-Item -Path (Join-Path $TestDrive "repo"), $script:UserData -Recurse -Force -ErrorAction SilentlyContinue
		$script:Source = Join-Path $script:Root "MyProfile"
		New-Item -ItemType Directory -Path (Join-Path $script:UserData "snippets") -Force | Out-Null
		Set-Content -Path (Join-Path $script:UserData "settings.json") -Value '{"editor.tabSize":4}'
		Set-Content -Path (Join-Path $script:UserData "keybindings.json") -Value '[]'

		$script:Section = @{
			Root      = $script:Root
			UserData  = $script:UserData
			Catalogue = @(@{ MyProfile = @{ Target = "Default" } })
		}
		Mock Get-ConfigSetting { $script:Section } -ParameterFilter { $Path -eq 'VSCodeProfiles' }
		# Tests that fake a symbolic link mock Get-Item for one path; every other path is real.
		Mock Get-Item { if ($LiteralPath) { & $script:RealGetItem -LiteralPath $LiteralPath -Force:$Force -ErrorAction SilentlyContinue } else { & $script:RealGetItem -Path $Path -Force:$Force -ErrorAction SilentlyContinue } }

		$env:WINUX_TEST_CODE_LIST = "a.kept@1.0.0;z.new@1.0.0"
		$script:Stub = Join-Path $TestDrive "code-stub.ps1"
		Set-Content -Path $script:Stub -Value @(
			"if (`$args[0] -eq '--list-extensions') { `$env:WINUX_TEST_CODE_LIST -split ';' | Where-Object { `$_ }; exit 0 }",
			"exit 1"
		)
	}

	AfterEach {
		Remove-Item -Path Env:\WINUX_TEST_CODE_LIST -ErrorAction SilentlyContinue
	}

	It "creates the profile folder and copies the profile's real files into it" {
		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Get-Content -Path (Join-Path $script:Source "settings.json") -Raw | Should -Match "editor.tabSize"
		Test-Path -Path (Join-Path $script:Source "keybindings.json") | Should -BeTrue
	}

	It "does not copy an empty snippets folder" {
		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Test-Path -Path (Join-Path $script:Source "snippets") | Should -BeFalse
	}

	It "copies the snippets a profile has" {
		Set-Content -Path (Join-Path $script:UserData "snippets\markdown.json") -Value "{}"

		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Test-Path -Path (Join-Path $script:Source "snippets\markdown.json") | Should -BeTrue
	}

	It "captures keybindings into keybindings.windows.json when the folder carries one" {
		New-Item -ItemType Directory -Path $script:Source -Force | Out-Null
		Set-Content -Path (Join-Path $script:Source "keybindings.windows.json") -Value "old"

		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Get-Content -Path (Join-Path $script:Source "keybindings.windows.json") -Raw | Should -Match "\[\]"
		Test-Path -Path (Join-Path $script:Source "keybindings.json") | Should -BeFalse
	}

	It "leaves a file that is linked into the repository alone" {
		New-Item -ItemType Directory -Path $script:Source -Force | Out-Null
		Set-Content -Path (Join-Path $script:Source "settings.json") -Value "repository copy"
		$live = Join-Path $script:UserData "settings.json"
		$repo = Join-Path $script:Source "settings.json"
		Mock Get-Item { [pscustomobject]@{ LinkType = "SymbolicLink"; Target = @($repo) } } -ParameterFilter { $LiteralPath -eq $live }

		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Get-Content -Path $repo -Raw | Should -Match "repository copy"
		Should -Invoke Write-LogWarning -Times 0
	}

	It "reports a link that points outside the repository and leaves it alone" {
		$live = Join-Path $script:UserData "settings.json"
		Mock Get-Item { [pscustomobject]@{ LinkType = "SymbolicLink"; Target = @("C:\Elsewhere\settings.json") } } -ParameterFilter { $LiteralPath -eq $live }

		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Test-Path -Path (Join-Path $script:Source "settings.json") | Should -BeFalse
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*Elsewhere*" }
	}

	It "merges the installed extensions into extensions.txt, keeping comments and dropping uninstalled ones" {
		New-Item -ItemType Directory -Path $script:Source -Force | Out-Null
		Set-Content -Path (Join-Path $script:Source "extensions.txt") -Value @("# kept", "a.kept@1.0.0", "b.gone")

		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		@(Get-Content -Path (Join-Path $script:Source "extensions.txt")) -join "|" | Should -Be "# kept|a.kept@1.0.0|z.new"
	}

	It "writes every installed extension, sorted and with no blank first line, when extensions.txt is new" {
		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		@(Get-Content -Path (Join-Path $script:Source "extensions.txt")) -join "|" | Should -Be "a.kept|z.new"
	}

	It "leaves extensions.txt alone when the extensions cannot be listed" {
		New-Item -ItemType Directory -Path $script:Source -Force | Out-Null
		Set-Content -Path (Join-Path $script:Source "extensions.txt") -Value "a.kept"
		Set-Content -Path $script:Stub -Value "exit 1"

		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Get-Content -Path (Join-Path $script:Source "extensions.txt") | Should -Be "a.kept"
		Should -Invoke Write-LogError -Times 1 -Exactly
	}

	It "refuses an entry the catalogue does not carry" {
		Export-VSCodeProfile -Name Missing -Command $script:Stub

		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like "*Missing*Catalogue*" }
		Test-Path -Path $script:Root | Should -BeFalse
	}

	It "refuses a profile VS Code does not have, without registering it" {
		$script:Section.Catalogue = @(@{ MyProfile = @{ Target = "Writing" } })

		Export-VSCodeProfile -Name MyProfile -Command $script:Stub

		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like "*Writing*" }
		Test-Path -Path (Join-Path $script:UserData "globalStorage\storage.json") | Should -BeFalse
	}
}
