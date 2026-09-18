#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Update-Repositories.ps1"
	# The selection resolver Update-Repositories delegates every mode to; dot-sourced so it
	# exists to Mock even in sessions whose imported Git module predates the export.
	. "$FunctionsPath\Resolve-RepositoryTargets.ps1"
}

Describe "Update-Repositories" {
	BeforeEach {
		$global:Configuration = @{ RepositoryGroups = @() }
		$script:GithubPat = ""

		Mock Test-AdminPrivileges { }
		Mock Resolve-ProjectPath { }
		Mock Resolve-RepositoryTargets { , @() }
		Mock Resolve-Selection { }
		Mock Get-RepositoryName { "repo" }
		Mock Test-Path { $false }
		Mock Initialize-Repository { }
		Mock Push-Location { }
		Mock Pop-Location { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Remove-Item { }
		Mock git { $global:LASTEXITCODE = 0 }
	}

	It "initializes repository when custom URL target path is missing" {
		Update-Repositories -RepositoryUrl "https://github.com/user/repo" -LocalPath "C:\Repos\repo"

		Should -Invoke Test-AdminPrivileges -Times 1
		Should -Invoke Initialize-Repository -Times 1 -ParameterFilter {
			$RepositoryUrl -eq "https://github.com/user/repo" -and
			$LocalPath -eq "C:\Repos\repo"
		}
	}

	Context "Parameter sets" {
		It "Should refuse a repository name and a group name in the same call" {
			{ Update-Repositories -Repositories "Zulu" -Group "Beta" } |
				Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
		}

		It "Should make -RepositoryUrl and -LocalPath mandatory together" {
			# Asserted off the metadata rather than by calling: a missing mandatory parameter
			# PROMPTS on an interactive host, which would hang the suite instead of failing it.
			$parameters = (Get-Command Update-Repositories).Parameters

			foreach ($name in @('RepositoryUrl', 'LocalPath')) {
				$attribute = @($parameters[$name].Attributes | Where-Object { $_ -is [Parameter] -and $_.ParameterSetName -eq 'Custom' })[0]
				$attribute | Should -Not -BeNullOrEmpty -Because "[$name] belongs to the Custom set"
				$attribute.Mandatory | Should -BeTrue -Because "[$name] is useless without its partner"
			}
		}

		It "Should refuse -All together with -Group" {
			{ Update-Repositories -All -Group "Beta" } |
				Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
		}
	}

	Context "Direct selection" {
		It "Should title a group run with the configured group spelling in brackets" {
			Mock Resolve-RepositoryTargets {
				, @([PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "u"; LocalPath = "C:\Repos\Mike" })
			} -ParameterFilter { $Group }

			Update-Repositories -Group "beta"

			Should -Invoke Write-LogTitle -Times 1 -Exactly -ParameterFilter { $Message -eq "Updating [Beta] Repositories" }
		}

		It "Should list every requested group in the title" {
			Mock Resolve-RepositoryTargets {
				, @(
					[PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "u"; LocalPath = "C:\Repos\Mike" }
					[PSCustomObject]@{ Name = "Zulu"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = "C:\Repos\Zulu" }
				)
			} -ParameterFilter { $Group }

			Update-Repositories -Group "Beta", "Alpha"

			Should -Invoke Write-LogTitle -Times 1 -Exactly -ParameterFilter { $Message -eq "Updating [Beta, Alpha] Repositories" }
		}

		It "Should update nothing when the group name is unknown" {
			Mock Resolve-RepositoryTargets { $null } -ParameterFilter { $Group }

			Update-Repositories -Group "Wrok"

			Should -Invoke Write-LogTitle -Times 0
			Should -Invoke Initialize-Repository -Times 0
		}

		It "Should route -All through the resolver" {
			Update-Repositories -All

			Should -Invoke Resolve-RepositoryTargets -Times 1 -Exactly -ParameterFilter { $All }
			Should -Invoke Write-LogTitle -Times 1 -Exactly -ParameterFilter { $Message -eq "Updating All Repositories" }
		}

		It "Should route names through the resolver instead of resolving them itself" {
			Update-Repositories -Repositories "Zulu", "Alfa"

			Should -Invoke Resolve-RepositoryTargets -Times 1 -Exactly -ParameterFilter {
				$Repositories -contains "Zulu" -and $Repositories -contains "Alfa"
			}
			Should -Invoke Resolve-ProjectPath -Times 0
		}
	}

	Context "Archive mode" {
		BeforeEach {
			Mock Get-RepositoryName { "DSA" }
			Mock Resolve-RepositoryTargets {
				, @([PSCustomObject]@{ Name = "DSA"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/DSA"; LocalPath = "C:\Repos\DSA" })
			}
		}

		It "Should never reach for git archive, which GitHub serves on no protocol" {
			# `git archive --remote` asks the server to run git-upload-archive. GitHub answers
			# HTTP 422 and git exits 128, so the attempt failed for every repository on every
			# branch and only ever printed a misleading "not supported" warning before the
			# shallow clone that actually did the work.
			Update-Repositories -Repositories "DSA" -Archive

			Should -Invoke git -Times 0 -ParameterFilter { $args -contains 'archive' }
		}

		It "Should shallow-clone and strip the .git directory" {
			Mock Test-Path { $true } -ParameterFilter { $Path -like '*\.git' }

			Update-Repositories -Repositories "DSA" -Archive

			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$args -contains 'clone' -and $args -contains '--depth' -and $args -contains '1'
			}
			Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $Path -like '*\.git' -and $Recurse }
		}

		It "Should target the Desktop by default and the current directory with -InCurrentDirectory" {
			Mock Get-Location { [PSCustomObject]@{ Path = "C:\Work" } }

			Update-Repositories -Repositories "DSA" -Archive
			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$args -contains ([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'DSA'))
			}

			Update-Repositories -Repositories "DSA" -Archive -InCurrentDirectory
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args -contains 'C:\Work\DSA' }
		}

		It "Should report a failed clone and not strip anything" {
			Mock git { $global:LASTEXITCODE = 128 }

			Update-Repositories -Repositories "DSA" -Archive

			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -match 'Failed to download' }
			Should -Invoke Remove-Item -Times 0
		}

		It "Should skip a target that already exists" {
			Mock Test-Path { $true }

			Update-Repositories -Repositories "DSA" -Archive

			Should -Invoke git -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match 'Already exists' }
		}
	}

	Context "Interactive menu" {
		BeforeEach {
			Mock Resolve-RepositoryTargets {
				, @(
					[PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" }
					[PSCustomObject]@{ Name = "Bravo"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Bravo"; LocalPath = "C:\Repos\Bravo" }
				)
			} -ParameterFilter { $All }
		}

		It "Should hand Resolve-Selection real repository URLs and no OptionList" {
			Mock Resolve-Selection { }

			Update-Repositories

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				-not $PSBoundParameters.ContainsKey('OptionList') -and
				@($GroupsConfig).Count -eq 1 -and
				@($GroupsConfig)[0]['Beta'][0].Url -eq "https://github.com/acme/Mike"
			}
		}

		It "Should expand a selected parent through the group resolver" {
			Mock Resolve-Selection { @([PSCustomObject]@{ IsParent = $true; PathNames = @('Beta') }) }

			Update-Repositories

			Should -Invoke Write-LogTitle -Times 1 -Exactly -ParameterFilter { $Message -eq "Updating [Beta] Repositories" }
			Should -Invoke Resolve-RepositoryTargets -Times 1 -Exactly -ParameterFilter { $Group -contains 'Beta' }
		}

		It "Should resolve a selected leaf by name" {
			Mock Resolve-Selection { @([PSCustomObject]@{ IsParent = $false; PathNames = @('Beta', 'Mike') }) }

			Update-Repositories

			Should -Invoke Write-LogTitle -Times 1 -Exactly -ParameterFilter { $Message -eq "Updating Selected Repositories" }
			Should -Invoke Resolve-RepositoryTargets -Times 1 -Exactly -ParameterFilter { $Repositories -contains 'Mike' }
		}

		It "Should update a repository picked both directly and through its group only once" {
			Mock Resolve-Selection {
				@(
					[PSCustomObject]@{ IsParent = $true; PathNames = @('Beta') }
					[PSCustomObject]@{ IsParent = $false; PathNames = @('Beta', 'Mike') }
				)
			}
			Mock Resolve-RepositoryTargets {
				, @([PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" })
			} -ParameterFilter { $Group -or $Repositories }

			Update-Repositories

			Should -Invoke Initialize-Repository -Times 1 -Exactly -ParameterFilter { $LocalPath -eq "C:\Repos\Mike" }
		}
	}
}
