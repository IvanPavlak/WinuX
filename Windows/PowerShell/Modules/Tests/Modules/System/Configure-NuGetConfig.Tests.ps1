#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-NuGetConfig.ps1"
}

Describe "Configure-NuGetConfig" {
	BeforeEach {
		$global:MachineSpecificPaths = [PSCustomObject]@{
			NuGetConfig = [PSCustomObject]@{
				SourcePath      = "C:\\WinuX\\NuGet\\nuget.config"
				DestinationPath = "C:\\Users\\You\\AppData\\Roaming\\NuGet\\NuGet.config"
			}
		}

		Mock Test-Path {
			if ($Path -eq "C:\\WinuX\\NuGet\\nuget.config") {
				$false
			}
			else {
				$false
			}
		}
		Mock Custom-ReadHost { "ignored" }
		Mock Write-Host { }
	}

	It "returns when source nuget.config is missing" {
		{ Configure-NuGetConfig } | Should -Not -Throw

		Should -Invoke Custom-ReadHost -Times 0
	}

	Context "with a template and an existing config on disk" {
		BeforeEach {
			$script:template = Join-Path $TestDrive "nuget.config"
			$script:target = Join-Path $TestDrive "AppData\NuGet\NuGet.Config"
			$script:backupRoot = Join-Path $TestDrive "Backups"
			Remove-Item -LiteralPath (Join-Path $TestDrive "AppData"), $script:backupRoot -Recurse -Force -ErrorAction SilentlyContinue
			New-Item -ItemType Directory -Path (Split-Path $script:target) -Force | Out-Null
			Set-Content -LiteralPath $script:template -Value @(
				'<configuration>', '  <packageSources>', '    <add key="MyFeed" value="https://nuget.pkg.github.com/MyOrg/index.json" />', '  </packageSources>',
				'  <packageSourceCredentials>', '    <MyFeed>', '      <add key="Username" value="[Username]" />', '      <add key="ClearTextPassword" value="[Token]" />',
				'    </MyFeed>', '  </packageSourceCredentials>', '</configuration>'
			)
			Set-Content -LiteralPath $script:target -Value @(
				'<configuration>', '  <packageSources>', '    <add key="Other" value="https://other.invalid" />', '  </packageSources>',
				'  <packageSourceCredentials>', '    <Other>', '      <add key="ClearTextPassword" value="old-token" />', '      <add value="old-password" key="Password" />',
				'    </Other>', '  </packageSourceCredentials>', '</configuration>'
			)
			$global:MachineSpecificPaths = [PSCustomObject]@{
				NuGetConfig = [PSCustomObject]@{ SourcePath = $script:template; DestinationPath = $script:target }
			}
			Mock Test-Path { Microsoft.PowerShell.Management\Test-Path -Path $Path }
			$script:tokens = [System.Collections.Generic.Queue[string]]::new()
			$script:tokens.Enqueue("new-token-1234")
			Mock Custom-ReadHost { "my-user" } -ParameterFilter { -not $AsSecureString }
			Mock Custom-ReadHost { [System.Net.NetworkCredential]::new('', $script:tokens.Dequeue()).SecurePassword } -ParameterFilter { $AsSecureString }
		}

		It "backs up the old config with every ClearTextPassword and Password redacted" {
			$tempBefore = @(Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter "nuget-*" -Directory -ErrorAction SilentlyContinue).Count

			Configure-NuGetConfig -Override -BackupRoot $script:backupRoot

			$backups = @(Get-ChildItem -Path (Join-Path $script:backupRoot "System\NuGetConfig") -Recurse -File -Force)
			$backups.Count | Should -Be 1
			$backups[0].Name | Should -Be "NuGet.Config"
			$backup = [System.IO.File]::ReadAllText($backups[0].FullName)
			$backup | Should -Match ([regex]::Escape('https://other.invalid'))
			$backup | Should -Match ([regex]::Escape('<add key="ClearTextPassword" value="REDACTED" />'))
			$backup | Should -Match ([regex]::Escape('<add value="REDACTED" key="Password" />'))
			$backup | Should -Not -Match 'old-token|old-password|new-token'
			@(Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter "nuget-*" -Directory -ErrorAction SilentlyContinue).Count | Should -Be $tempBefore
			Get-Content -LiteralPath $script:target -Raw | Should -Match 'value="new-token-1234"'
		}

		It "asks again for a token with whitespace in it (a pasted command)" {
			$script:tokens.Clear()
			$script:tokens.Enqueue("Configure-NuGetConfig -Override")
			$script:tokens.Enqueue("new-token-1234")

			Configure-NuGetConfig -Override -BackupRoot $script:backupRoot

			Should -Invoke Custom-ReadHost -Times 2 -Exactly -ParameterFilter { $AsSecureString }
			$written = Get-Content -LiteralPath $script:target -Raw
			$written | Should -Match 'value="new-token-1234"'
			$written | Should -Not -Match 'Configure-NuGetConfig'
		}
	}
}
