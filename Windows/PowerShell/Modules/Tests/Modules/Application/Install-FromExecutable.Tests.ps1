#Requires -Modules Pester

BeforeAll {
	$script:OriginalUserProfile = $env:USERPROFILE
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-FromExecutable.ps1"
}

AfterAll {
	$env:USERPROFILE = $script:OriginalUserProfile
}

Describe "Install-FromExecutable" {
	BeforeEach {
		$env:USERPROFILE = 'C:\Users\You'
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogSuccess { }
		Mock Test-AdminPrivileges { }
		Mock New-Item { }
		Mock Invoke-WebRequest { }
		Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
		Mock Custom-ReadHost { 'ok' }
		Mock Remove-Item { }
		Mock Test-Path { $false }
	}

	Context "Download + interactive (GUI) mode" {
		It "downloads, launches the installer, waits, and cleans up on success" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe'

			Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://example.com/setup.exe' }
			Should -Invoke Start-Process -Times 1 -Exactly
			Should -Invoke Custom-ReadHost -Times 1 -Exactly
			Should -Invoke Remove-Item -Times 1 -Exactly
			Should -Invoke Write-LogSuccess -Times 1 -Exactly
		}

		It "still cleans up and logs an error when the download fails" {
			Mock Invoke-WebRequest { throw 'network error' }

			{ Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -MaxAttempts 1 } | Should -Not -Throw

			Should -Invoke Write-LogError -Times 1
			Should -Invoke Start-Process -Times 0
			Should -Invoke Remove-Item -Times 1 -Exactly
			Should -Invoke Write-LogSuccess -Times 0
		}

		It "retries a flaky download and proceeds once it succeeds" {
			$script:downloadAttempts = 0
			Mock Invoke-WebRequest {
				$script:downloadAttempts++
				if ($script:downloadAttempts -lt 3) { throw 'transient network error' }
			}

			{ Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -MaxAttempts 3 } | Should -Not -Throw

			Should -Invoke Invoke-WebRequest -Times 3 -Exactly
			Should -Invoke Start-Process -Times 1 -Exactly
			Should -Invoke Write-LogSuccess -Times 1 -Exactly
		}
	}

	Context "Installer file name resolution" {
		It "saves the download under the URL's file name when it has an installer extension" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/dl/7z2408-x64.exe'
			Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { [System.IO.Path]::GetFileName($OutFile) -eq '7z2408-x64.exe' }
		}

		It "falls back to installer.exe when the URL has no recognized installer extension" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/download.aspx?id=5'
			Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { [System.IO.Path]::GetFileName($OutFile) -eq 'installer.exe' }
		}

		It "honors an explicit -InstallerName override" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/download?token=x' -InstallerName 'custom-setup.exe'
			Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { [System.IO.Path]::GetFileName($OutFile) -eq 'custom-setup.exe' }
		}

		It "derives a sanitized installer name from a URL containing invalid path characters (no throw)" {
			{ Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/a|b.exe' } | Should -Not -Throw
			Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { [System.IO.Path]::GetFileName($OutFile) -eq 'ab.exe' }
		}

		It "strips directory components and invalid characters from an explicit -InstallerName" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/download' -InstallerName '..\ev|il.exe'
			Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { [System.IO.Path]::GetFileName($OutFile) -eq 'evil.exe' }
		}
	}

	Context "Unattended (silent) mode" {
		It "runs the installer with -Wait and the given arguments, gating success on exit code 0" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -Arguments '/S'

			Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $Wait -eq $true -and $ArgumentList -contains '/S' }
			Should -Invoke Custom-ReadHost -Times 0
			Should -Invoke Write-LogSuccess -Times 1 -Exactly
			Should -Invoke Write-LogError -Times 0
		}

		It "reports a failure when the installer returns a non-zero exit code" {
			Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }

			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -Arguments '/S'

			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Write-LogSuccess -Times 0
		}

		It "treats a caller-supplied valid exit code as success" {
			Mock Start-Process { [pscustomobject]@{ ExitCode = 42 } }

			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -Arguments '/S' -ValidExitCodes 42

			Should -Invoke Write-LogSuccess -Times 1 -Exactly
			Should -Invoke Write-LogError -Times 0
		}

		It "warns about a required reboot but still reports success on exit code 3010" {
			Mock Start-Process { [pscustomobject]@{ ExitCode = 3010 } }

			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -Arguments '/S'

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'reboot' }
			Should -Invoke Write-LogSuccess -Times 1 -Exactly
			Should -Invoke Write-LogError -Times 0
		}

		It "runs unattended (never blocking on a prompt) even when -Arguments is empty" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -Arguments ''

			Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $Wait -eq $true }
			Should -Invoke Custom-ReadHost -Times 0
		}
	}

	Context "Local installer path" {
		It "runs a caller-supplied installer in place without downloading or deleting it" {
			Mock Test-Path { $true }

			Install-FromExecutable -Name 'Demo App' -Path 'D:\installers\setup.exe' -Arguments '/quiet'

			Should -Invoke Invoke-WebRequest -Times 0
			Should -Invoke New-Item -Times 0
			Should -Invoke Start-Process -Times 1 -Exactly
			Should -Invoke Remove-Item -Times 0
		}

		It "errors out when the local installer does not exist" {
			Mock Test-Path { $false }

			Install-FromExecutable -Name 'Demo App' -Path 'D:\installers\missing.exe' -Arguments '/quiet'

			Should -Invoke Write-LogError -Times 1
			Should -Invoke Start-Process -Times 0
		}
	}

	Context "Idempotency and elevation" {
		It "returns early when the detection path already exists" {
			Mock Test-Path { param($LiteralPath) $LiteralPath -eq 'C:\Program Files\Demo\demo.exe' }

			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -DetectionPath 'C:\Program Files\Demo\demo.exe'

			Should -Invoke Write-LogWarning -Times 1
			Should -Invoke Invoke-WebRequest -Times 0
			Should -Invoke Start-Process -Times 0
		}

		It "checks for admin privileges only when -RequireAdmin is set" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe' -RequireAdmin
			Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
		}

		It "does not require admin by default" {
			Install-FromExecutable -Name 'Demo App' -Url 'https://example.com/setup.exe'
			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
		}
	}
}
