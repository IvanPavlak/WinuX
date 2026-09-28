#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Install-Git.ps1"

	# Stub winget so it exists and can be mocked on machines (CI runners) that lack it.
	function winget { }
}

Describe "Install-Git" {
	BeforeEach {
		# The install branch rebuilds $env:Path from the registry, which drops process-only
		# entries and breaks command lookup for every later test in the same session.
		$script:OriginalPath = $env:Path

		$global:Configuration = @{
			GitConfig = @{
				WingetPackageId = "Git.Git"
				UserName        = "ExampleUser"
				UserEmail       = "user@example.com"
			}
		}

		Mock Write-Host { }
		Mock winget { }
		Mock git {
			if ($args[0] -eq "config" -and $args[1] -eq "--global" -and $args[2] -eq "user.name" -and $args.Count -eq 3) {
				return "ExampleUser"
			}
			if ($args[0] -eq "config" -and $args[1] -eq "--global" -and $args[2] -eq "user.email" -and $args.Count -eq 3) {
				return "user@example.com"
			}
		}
	}

	AfterEach {
		$env:Path = $script:OriginalPath
	}

	It "installs git with winget when git command is missing" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "git" }

		Install-Git

		Should -Invoke winget -Times 1 -ParameterFilter { $args[0] -eq "install" }
		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "config" -and $args[1] -eq "--system" -and $args[2] -eq "core.longpaths" }
	}

	It "skips winget install when git command already exists" {
		Mock Get-Command { @{ Name = "git" } } -ParameterFilter { $Name -eq "git" }

		Install-Git

		Should -Invoke winget -Times 0
		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "config" -and $args[1] -eq "--global" -and $args[2] -eq "user.name" -and $args.Count -gt 3 }
		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "config" -and $args[1] -eq "--global" -and $args[2] -eq "user.email" -and $args.Count -gt 3 }
	}
}
