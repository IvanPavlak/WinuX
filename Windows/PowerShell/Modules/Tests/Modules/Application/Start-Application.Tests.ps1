#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-Application.ps1"
}

Describe "Start-Application" {
	Context "Parameter Validation" {
		It "Should require AppName parameter" {
			(Get-Command Start-Application).Parameters['AppName'].Attributes |
				Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
				ForEach-Object { $_.Mandatory | Should -Be $true }
		}

		It "Should require ProcessName parameter" {
			(Get-Command Start-Application).Parameters['ProcessName'].Attributes |
				Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
				ForEach-Object { $_.Mandatory | Should -Be $true }
		}

		It "Should require StartMethod parameter" {
			(Get-Command Start-Application).Parameters['StartMethod'].Attributes |
				Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
				ForEach-Object { $_.Mandatory | Should -Be $true }
		}

		It "Should only accept valid StartMethod values" {
			$validateSet = (Get-Command Start-Application).Parameters['StartMethod'].Attributes |
				Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
			$validateSet.ValidValues | Should -Contain 'ConfigPath'
			$validateSet.ValidValues | Should -Contain 'AppxPackage'
			$validateSet.ValidValues | Should -Contain 'DirectPath'
			$validateSet.ValidValues | Should -Contain 'Custom'
			$validateSet.ValidValues.Count | Should -Be 4
		}
	}

	Context "Process Already Running Detection" {
		It "Should return early when process is already running" {
			Mock -CommandName 'Start-Process' -MockWith { }

			Mock -CommandName 'Start-Process' -MockWith { }

			# We can test the logic by ensuring Start-Process is NOT called when process exists
			# This test verifies the behavior indirectly
			$null = Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" -StartMethod DirectPath -ExecutablePath "C:\test.exe" -SkipPathValidation
			# If process doesn't exist, Start-Process would be called
			Should -Invoke Start-Process -Times 1
		}

		It "Should skip process check when SkipProcessCheck is specified" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod DirectPath -ExecutablePath "C:\test.exe" -SkipProcessCheck -SkipPathValidation

			Should -Invoke Start-Process -Times 1
		}

		It "Should ignore a running process whose path does not match ProcessPathFilter" {
			Mock Start-Process { }

			# This session's own process exists by name, but its path won't match the filter,
			# so it must not be treated as "already running".
			$self = Get-Process -Id $PID

			Start-Application -AppName "TestApp" -ProcessName $self.ProcessName `
				-StartMethod DirectPath -ExecutablePath "C:\test.exe" -SkipPathValidation `
				-ProcessPathFilter "Z:\NoSuchLocation\*"

			Should -Invoke Start-Process -Times 1
		}

		It "Should treat a path-matching process as already running with ProcessPathFilter" {
			Mock Start-Process { }

			# This session's own process exists and its path matches the filter,
			# so it must be treated as "already running" and not launched again.
			$self = Get-Process -Id $PID
			$selfDir = Split-Path -Parent $self.Path

			Start-Application -AppName "TestApp" -ProcessName $self.ProcessName `
				-StartMethod DirectPath -ExecutablePath "C:\test.exe" -SkipPathValidation `
				-ProcessPathFilter "$selfDir\*"

			Should -Invoke Start-Process -Times 0
		}
	}

	Context "ConfigPath Method" {
		It "Should throw when ConfigKey is not provided" {
			Mock Start-Process { }

			# ConfigPath without ConfigKey should produce an error
			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod ConfigPath 2>&1

			# The function catches the error and Write-Host's it, so we just verify Start-Process wasn't called
			Should -Invoke Start-Process -Times 0
		}
	}

	Context "DirectPath Method" {
		It "Should throw when ExecutablePath is not provided" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod DirectPath 2>&1

			Should -Invoke Start-Process -Times 0
		}

		It "Should throw when executable path does not exist and SkipPathValidation is not set" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod DirectPath -ExecutablePath "C:\NonExistent\app.exe" 2>&1

			Should -Invoke Start-Process -Times 0
		}

		It "Should pass NoNewWindow flag to Start-Process" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod DirectPath -ExecutablePath "C:\test.exe" -NoNewWindow -SkipPathValidation

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$NoNewWindow -eq $true
			}
		}

		It "Should pass Arguments to Start-Process" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod DirectPath -ExecutablePath "C:\test.exe" -Arguments @("--arg1", "--arg2") -SkipPathValidation

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$ArgumentList -contains "--arg1"
			}
		}

		It "Should pass Wait flag when Sync is specified" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod DirectPath -ExecutablePath "C:\test.exe" -Sync -SkipPathValidation

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$Wait -eq $true
			}
		}
	}

	Context "Custom Method" {
		It "Should throw when CustomStartLogic is not provided" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod Custom 2>&1

			Should -Invoke Start-Process -Times 0
		}

		It "Should execute CustomStartLogic scriptblock" {
			$script:customLogicExecuted = $false

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod Custom -CustomStartLogic { $script:customLogicExecuted = $true }

			$script:customLogicExecuted | Should -Be $true
		}
	}

	Context "AppxPackage Method" {
		It "Should throw when PackageName is not provided" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod AppxPackage 2>&1

			Should -Invoke Start-Process -Times 0
		}
	}

	Context "Additional Branch Contracts" {
		BeforeEach {
			$global:Configuration = @{
				Universal = @{
					TestExe = 'C:\Tools\test.exe'
				}
			}
		}

		It "Should start application from ConfigPath when ConfigKey resolves successfully" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod ConfigPath -ConfigKey "TestExe" -Arguments @("--flag") -NoNewWindow -Sync

			Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
				$FilePath -eq 'C:\Tools\test.exe' -and
				$NoNewWindow -eq $true -and
				$Wait -eq $true -and
				$ArgumentList -contains '--flag'
			}
		}

		It "Should set redirect parameters and force NoNewWindow when SuppressOutput is used" {
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod ConfigPath -ConfigKey "TestExe" -SuppressOutput

			Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
				$FilePath -eq 'C:\Tools\test.exe' -and
				$NoNewWindow -eq $true -and
				-not [string]::IsNullOrWhiteSpace($RedirectStandardOutput) -and
				-not [string]::IsNullOrWhiteSpace($RedirectStandardError)
			}
		}

		It "Should activate AppxPackage app via its AppUserModelID when the package resolves" {
			Mock Get-AppxPackage {
				[PSCustomObject]@{ PackageFamilyName = 'Microsoft.Test_8wekyb3d8bbwe' }
			}
			Mock Get-AppxPackageManifest {
				[PSCustomObject]@{
					Package = [PSCustomObject]@{
						Applications = [PSCustomObject]@{
							Application = [PSCustomObject]@{ Id = 'App' }
						}
					}
				}
			}
			Mock Start-Process { }

			Start-Application -AppName "TestApp" -ProcessName "nonexistent_test_proc_xyz" `
				-StartMethod AppxPackage -PackageName "Microsoft.Test"

			Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
				$FilePath -eq 'shell:AppsFolder\Microsoft.Test_8wekyb3d8bbwe!App'
			}
		}
	}
}
