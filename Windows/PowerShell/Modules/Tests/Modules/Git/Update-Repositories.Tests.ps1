#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Update-Repositories.ps1"
	# The selection resolver Update-Repositories delegates every mode to; dot-sourced so it
	# exists to Mock even in sessions whose imported Git module predates the export.
	. "$FunctionsPath\Resolve-RepositoryTargets.ps1"
	. "$FunctionsPath\Update-Repository.ps1"
	. "$FunctionsPath\Format-RepositoryUpdateResult.ps1"
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

	Context "Administrator only to clone" {
		BeforeEach {
			Mock Update-Repository { [pscustomobject]@{ Name = $Name; Branch = "master"; Outcome = "UpToDate"; DefaultBranch = $null; DefaultBranchOutcome = $null; StashName = $null } }
			Mock Resolve-RepositoryTargets {
				, @(
					[PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" }
					[PSCustomObject]@{ Name = "Zulu"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Zulu"; LocalPath = "C:\Repos\Zulu" }
				)
			}
		}

		It "never asks for Administrator when every repository is already on disk" {
			Mock Test-Path { $true }

			Update-Repositories -All

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Update-Repository -Times 2 -Exactly
		}

		It "asks once when any repository has to be cloned" {
			Mock Test-Path { $LiteralPath -ne "C:\Repos\Zulu" -and $Path -ne "C:\Repos\Zulu" }

			Update-Repositories -All

			Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
			Should -Invoke Initialize-Repository -Times 1 -Exactly -ParameterFilter { $LocalPath -eq "C:\Repos\Zulu" }
			Should -Invoke Update-Repository -Times 1 -Exactly -ParameterFilter { $LocalPath -eq "C:\Repos\Mike" }
		}

		It "with -NoClone skips missing repositories without cloning or asking" {
			Update-Repositories -All -NoClone

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Initialize-Repository -Times 0 -Exactly
			Should -Invoke Update-Repository -Times 0 -Exactly
		}

		It "still asks in archive mode, which only clones" {
			Mock Test-Path { $true }

			Update-Repositories -All -Archive

			Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
		}
	}

	Context "Default branch switch" {
		BeforeEach {
			Mock Test-Path { $true }
			Mock Update-Repository { [pscustomobject]@{ Name = $Name; Branch = "feature"; Outcome = "UpToDate"; DefaultBranch = $null; DefaultBranchOutcome = $null; StashName = $null } }
			Mock Resolve-RepositoryTargets {
				, @([PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" })
			}
		}

		It "follows RepositoryUpdate.IncludeDefaultBranch when the switch is not given (<Configured>)" -ForEach @(
			@{ Configured = $true }
			@{ Configured = $false }
		) {
			$global:Configuration = @{ RepositoryGroups = @(); RepositoryUpdate = @{ IncludeDefaultBranch = $Configured } }

			Update-Repositories -All

			Should -Invoke Update-Repository -Times 1 -Exactly -ParameterFilter { [bool]$IncludeDefaultBranch -eq $Configured }
		}

		It "is off when configuration says nothing" {
			Update-Repositories -All

			Should -Invoke Update-Repository -Times 1 -Exactly -ParameterFilter { -not $IncludeDefaultBranch }
		}

		It "-IncludeDefaultBranch turns it on over configuration" {
			$global:Configuration = @{ RepositoryGroups = @(); RepositoryUpdate = @{ IncludeDefaultBranch = $false } }

			Update-Repositories -All -IncludeDefaultBranch

			Should -Invoke Update-Repository -Times 1 -Exactly -ParameterFilter { $IncludeDefaultBranch }
		}

		It "-IncludeDefaultBranch:`$false turns it off over configuration" {
			$global:Configuration = @{ RepositoryGroups = @(); RepositoryUpdate = @{ IncludeDefaultBranch = $true } }

			Update-Repositories -All -IncludeDefaultBranch:$false

			Should -Invoke Update-Repository -Times 1 -Exactly -ParameterFilter { -not $IncludeDefaultBranch }
		}
	}

	Context "Quiet summary" {
		BeforeEach {
			Mock Resolve-RepositoryTargets {
				, @(
					[PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" }
					[PSCustomObject]@{ Name = "Zulu"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Zulu"; LocalPath = "C:\Repos\Zulu" }
					[PSCustomObject]@{ Name = "Kilo"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Kilo"; LocalPath = "C:\Repos\Kilo" }
				)
			}
			Mock Get-RepositoryName { Split-Path $RepositoryUrl -Leaf }
			Mock Test-Path { $LiteralPath -ne "C:\Repos\Kilo" -and $Path -ne "C:\Repos\Kilo" }
			Mock Update-Repository {
				$outcome = if ($Name -eq "Mike") { "Updated" } else { "Conflict" }
				[pscustomobject]@{ Name = $Name; Branch = "master"; Outcome = $outcome; DefaultBranch = $null; DefaultBranchOutcome = $null; StashName = $null }
			}
		}

		It "hands -Quiet down to every repository update" {
			Update-Repositories -All -Quiet -NoClone

			Should -Invoke Update-Repository -Times 2 -Exactly -ParameterFilter { $Quiet }
		}

		It "prints one line per repository and the totals, at the level each one needs" {
			Update-Repositories -All -Quiet -NoClone

			# Mike updated (success), Zulu conflict (warning), Kilo not cloned (success), then the
			# totals as a warning because one repository needs attention.
			Should -Invoke Write-LogSuccess -Times 2 -Exactly
			Should -Invoke Write-LogWarning -Times 2 -Exactly
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter {
				$Message -match "1 updated" -and $Message -match "1 need attention" -and $Message -match "1 skipped"
			}
		}

		It "prints no summary without -Quiet" {
			Update-Repositories -All -NoClone

			Should -Invoke Write-LogSuccess -Times 0 -Exactly -ParameterFilter { $Message -match "^Repositories =>" }
			Should -Invoke Write-LogWarning -Times 0 -Exactly -ParameterFilter { $Message -match "^Repositories =>" }
		}

		It "returns nothing to the pipeline" {
			$output = @(Update-Repositories -All -Quiet -NoClone)

			$output.Count | Should -Be 0
		}
	}

	Context "Group headings" {
		BeforeEach {
			Mock Test-Path { $true }
			Mock Get-RepositoryName { Split-Path $RepositoryUrl -Leaf }
			Mock Update-Repository { [pscustomobject]@{ Name = $Name; Branch = "master"; Outcome = "UpToDate"; DefaultBranch = $null; DefaultBranchOutcome = $null; StashName = $null } }
		}

		It "prints one heading per group, in resolution order, when a run spans several groups" {
			Mock Resolve-RepositoryTargets {
				, @(
					[PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" }
					[PSCustomObject]@{ Name = "Kilo"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Kilo"; LocalPath = "C:\Repos\Kilo" }
					[PSCustomObject]@{ Name = "Zulu"; Group = "Alpha"; RepositoryUrl = "https://github.com/acme/Zulu"; LocalPath = "C:\Repos\Zulu" }
				)
			}
			$script:Titles = [System.Collections.Generic.List[string]]::new()
			Mock Write-LogTitle { $script:Titles.Add($Message) }

			Update-Repositories -All -Quiet

			$script:Titles -join "|" | Should -Be "Updating All Repositories|Beta|Alpha"
		}

		It "separates a heading from its first line only, with a blank line" {
			Mock Resolve-RepositoryTargets {
				, @(
					[PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" }
					[PSCustomObject]@{ Name = "Kilo"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Kilo"; LocalPath = "C:\Repos\Kilo" }
					[PSCustomObject]@{ Name = "Zulu"; Group = "Alpha"; RepositoryUrl = "https://github.com/acme/Zulu"; LocalPath = "C:\Repos\Zulu" }
				)
			}

			Update-Repositories -All -Quiet

			Should -Invoke Write-LogSuccess -Times 2 -Exactly -ParameterFilter { $Message -match "^\[(Mike|Zulu)\]" -and -not $NoLeadingNewline }
			Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -match "^\[Kilo\]" -and $NoLeadingNewline }
		}

		It "prints no group heading when the run covers one group" {
			Mock Resolve-RepositoryTargets {
				, @(
					[PSCustomObject]@{ Name = "Mike"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Mike"; LocalPath = "C:\Repos\Mike" }
					[PSCustomObject]@{ Name = "Kilo"; Group = "Beta"; RepositoryUrl = "https://github.com/acme/Kilo"; LocalPath = "C:\Repos\Kilo" }
				)
			}

			Update-Repositories -All -Quiet

			Should -Invoke Write-LogTitle -Times 1 -Exactly
			Should -Invoke Write-LogSuccess -Times 2 -Exactly -ParameterFilter { $Message -match "^\[(Mike|Kilo)\]" -and $NoLeadingNewline }
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
