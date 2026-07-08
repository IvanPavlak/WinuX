#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Git-Obsidian.ps1"
}

Describe "Git-Obsidian" {
	BeforeEach {
		$script:MachineSpecificPaths = @{ ObsidianDirectory = "C:\Vault" }
		$script:currentDirectory = "C:\Start"

		Mock Set-Location { }
		Mock Write-Host { }
		Mock git { }
	}

	It "commits and pushes when changes exist" {
		Mock git {
			if ($args[0] -eq "status") {
				return "M note.md"
			}
		}

		Git-Obsidian

		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "add" -and $args[1] -eq "." }
		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "commit" -and $args[1] -eq "-m" }
		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "push" }
	}

	It "skips commit and push when there are no changes" {
		Mock git {
			if ($args[0] -eq "status") {
				return ""
			}
		}

		Git-Obsidian

		Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "add" }
		Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "commit" }
		Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "push" }
	}
}
