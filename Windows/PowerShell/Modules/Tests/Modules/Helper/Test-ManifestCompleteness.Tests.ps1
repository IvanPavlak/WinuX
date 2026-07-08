#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-ManifestCompleteness.ps1"
}

Describe "Test-ManifestCompleteness" {
	BeforeEach {
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogSuccess { }
	}

	It "reports an error when the modules path does not exist" {
		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{
					Modules = (Join-Path $TestDrive 'DoesNotExist')
				}
			}
		}

		Test-ManifestCompleteness

		Should -Invoke Write-LogError -Times 1
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "warns when a function file is missing from the module manifest" {
		$root = Join-Path $TestDrive 'ModulesMissing'
		$fnDir = Join-Path $root 'Sample\Functions'
		New-Item -ItemType Directory -Path $fnDir -Force | Out-Null
		Set-Content -Path (Join-Path $root 'Sample\Sample.psd1') -Value "@{ FunctionsToExport = @('Get-Foo') }"
		Set-Content -Path (Join-Path $fnDir 'Get-Foo.ps1') -Value 'function Get-Foo { }'
		Set-Content -Path (Join-Path $fnDir 'Get-Bar.ps1') -Value 'function Get-Bar { }'

		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{ Modules = $root }
			}
		}

		Test-ManifestCompleteness

		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "reports success when every function file is exported" {
		$root = Join-Path $TestDrive 'ModulesComplete'
		$fnDir = Join-Path $root 'Sample\Functions'
		New-Item -ItemType Directory -Path $fnDir -Force | Out-Null
		Set-Content -Path (Join-Path $root 'Sample\Sample.psd1') -Value "@{ FunctionsToExport = @('Get-Foo', 'Get-Bar') }"
		Set-Content -Path (Join-Path $fnDir 'Get-Foo.ps1') -Value 'function Get-Foo { }'
		Set-Content -Path (Join-Path $fnDir 'Get-Bar.ps1') -Value 'function Get-Bar { }'

		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{ Modules = $root }
			}
		}

		Test-ManifestCompleteness

		Should -Invoke Write-LogSuccess -Times 1
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogError -Times 0
	}

	It "skips directories that have no manifest or no Functions folder" {
		$root = Join-Path $TestDrive 'ModulesPartial'
		# A bare directory with neither a manifest nor a Functions/ folder must be ignored.
		New-Item -ItemType Directory -Path (Join-Path $root 'NotAModule') -Force | Out-Null

		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{ Modules = $root }
			}
		}

		Test-ManifestCompleteness

		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogSuccess -Times 0
	}
}
