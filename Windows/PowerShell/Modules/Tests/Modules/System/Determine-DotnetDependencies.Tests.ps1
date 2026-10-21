#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Determine-DotnetDependencies.ps1"
}

Describe "Determine-DotnetDependencies" {
	BeforeEach {
		Mock Test-Path { $false }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "returns when the provided search path does not exist" {
		{ Determine-DotnetDependencies -SearchPath "C:\\Missing" } | Should -Not -Throw
		Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "C:\\Missing" }
		Should -Invoke Write-LogError -Times 1
	}

	Context "default search path" {
		BeforeEach {
			$script:SavedConfiguration = $global:Configuration
			$script:SavedMachineSpecificPaths = $global:MachineSpecificPaths
			$script:SavedMachineType = $global:MachineType
			$global:MachineType = "PC"
			$global:MachineSpecificPaths = @{}
		}

		AfterEach {
			$global:Configuration = $script:SavedConfiguration
			$global:MachineSpecificPaths = $script:SavedMachineSpecificPaths
			$global:MachineType = $script:SavedMachineType
		}

		It "expands the top-level DotnetProjectsSearchPath for this machine type" {
			# The key sits outside PathTemplates, so it used to be looked up in MachineSpecificPaths,
			# never found, and the scan always fell back to the profile's Development folder.
			$global:Configuration = @{
				DotnetProjectsSearchPath = "{Dev}\Projects"
				BasePaths                = @{ PC = @{ Dev = "D:\Dev"; User = "C:\Users\Someone" } }
			}

			Determine-DotnetDependencies

			Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "D:\Dev\Projects" }
		}

		It "lets a DotnetProjectsSearchPath placed under PathTemplates win" {
			$global:Configuration = @{
				DotnetProjectsSearchPath = "{Dev}\Projects"
				BasePaths                = @{ PC = @{ Dev = "D:\Dev"; User = "C:\Users\Someone" } }
			}
			$global:MachineSpecificPaths = @{ DotnetProjectsSearchPath = "E:\Code" }

			Determine-DotnetDependencies

			Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "E:\Code" }
		}

		It "falls back to the profile's Development folder when nothing is configured" {
			$global:Configuration = @{ DotnetProjectsSearchPath = "" }

			Determine-DotnetDependencies

			Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "$env:USERPROFILE\Development" }
		}

		It "falls back when the placeholders cannot be expanded for this machine type" {
			$global:Configuration = @{ DotnetProjectsSearchPath = "{Dev}\Projects"; BasePaths = @{} }

			Determine-DotnetDependencies

			Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "$env:USERPROFILE\Development" }
		}
	}

	Context "exclusions" {
		BeforeAll {
			# dotnet is absent on some CI runners; stub it so Mock can attach.
			if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
				function script:dotnet { }
			}
		}

		BeforeEach {
			Mock dotnet { }
			Mock Test-Path { $true }
			Mock Write-LogTitle { }
			Mock Write-LogStep { }
			Mock Write-LogWarning { }
			Mock Write-LogSuccess { }

			$script:Root = Join-Path $TestDrive "scan"
			foreach ($relative in @("Cabinet\App\App.csproj", "Tool\bin\Debug\Copy.csproj", "Lib\obj\Lib.csproj")) {
				$file = Join-Path $script:Root $relative
				New-Item -ItemType Directory -Path (Split-Path $file) -Force | Out-Null
				Set-Content -Path $file -Value "<Project />"
			}

			$script:parsed = [System.Collections.Generic.List[string]]::new()
			Mock Get-Content {
				$script:parsed.Add([string]$Path)
				"<Project><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>"
			}
		}

		It "excludes whole folder names only, so bin does not exclude Cabinet" {
			# The exclusion used to be a substring match on the full path.
			Determine-DotnetDependencies -SearchPath $script:Root

			@($script:parsed | Split-Path -Leaf) | Should -Be @("App.csproj")
		}

		It "matches an exclusion containing a separator as part of the path" {
			Determine-DotnetDependencies -SearchPath $script:Root -ExcludePaths @("Cabinet\App")

			@($script:parsed | Split-Path -Leaf | Sort-Object) | Should -Be @("Copy.csproj", "Lib.csproj")
		}
	}
}
