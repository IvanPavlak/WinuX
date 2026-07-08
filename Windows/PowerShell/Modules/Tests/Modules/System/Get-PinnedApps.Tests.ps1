#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-PinnedApps.ps1"
}

Describe "Get-PinnedApps" {
	BeforeEach {
		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{
					Root = "C:\\Repo"
				}
			}
		}
		Mock Import-CSV {
			@(
				[PSCustomObject]@{ App = "git"; Version = "2.44.0" },
				[PSCustomObject]@{ App = "nodejs"; Version = "Latest" }
			)
		}
	}

	It "returns only pinned apps when VersionExcludeValue is provided" {
		$result = Get-PinnedApps -CsvFileName "Windows/bootstrap/WinGetApps.csv" -VersionExcludeValue "Latest"

		$result | Should -Contain "git"
		$result | Should -Not -Contain "nodejs"
	}

	It "ignores CSV documentation-comment and blank rows" {
		# A '#'-comment line that contains commas is parsed by Import-Csv into a bogus row with a
		# non-"Latest" Version. It must NOT be reported as pinned - that garbage is what was fed to
		# `winget pin add` and hung the unattended upgrade on a fresh machine.
		Mock Import-CSV {
			@(
				[PSCustomObject]@{ App = "git"; Version = "2.44.0" },
				[PSCustomObject]@{ App = "#   Scope       d (default)"; Version = " m (machine-wide)" },
				[PSCustomObject]@{ App = "   #   Machine     where to install: `"All`""; Version = " `"Test`"" },
				[PSCustomObject]@{ App = ""; Version = "" }
			)
		}

		$result = Get-PinnedApps -CsvFileName "Windows/bootstrap/WinGetApps.csv" -VersionExcludeValue "Latest"

		$result | Should -Contain "git"
		$result | Where-Object { $_ -like "*#*" } | Should -BeNullOrEmpty
	}
}
