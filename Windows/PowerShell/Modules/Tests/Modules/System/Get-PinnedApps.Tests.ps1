#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-PinnedApps.ps1"
	# The layered reader Get-PinnedApps now reads through. Dot-sourced so it exists as a command the
	# filtering tests can Mock, and so the real one is available to the overlay test.
	. (Join-Path $ModuleRoot "Bootstrap\Functions\Import-AppCsv.ps1")

	# Import-AppCsv reports its layering counts through the Logging module; a no-op stub keeps these
	# tests free of that import.
	function Write-LogDebug {
		param(
			[Parameter(ValueFromRemainingArguments = $true)]
			$Arguments
		)
	}
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Get-PinnedApps" {
	Context "Selecting the pinned rows" {
		BeforeEach {
			Mock Import-AppCsv {
				@(
					[PSCustomObject]@{ App = "git"; Version = "2.44.0" },
					[PSCustomObject]@{ App = "nodejs"; Version = "Latest" }
				)
			}
		}

		It "returns only pinned apps when VersionExcludeValue is provided" {
			$result = Get-PinnedApps -DataFileKey WinGetApps -VersionExcludeValue "Latest"

			$result | Should -Contain "git"
			$result | Should -Not -Contain "nodejs"
		}

		It "ignores CSV documentation-comment and blank rows" {
			# A '#'-comment line that contains commas is parsed by Import-Csv into a bogus row with a
			# non-"Latest" Version. It must NOT be reported as pinned - that garbage is what was fed to
			# `winget pin add` and hung the unattended upgrade on a fresh machine.
			Mock Import-AppCsv {
				@(
					[PSCustomObject]@{ App = "git"; Version = "2.44.0" },
					[PSCustomObject]@{ App = "#   Scope       d (default)"; Version = " m (machine-wide)" },
					[PSCustomObject]@{ App = "   #   Machine     where to install: `"All`""; Version = " `"Test`"" },
					[PSCustomObject]@{ App = ""; Version = "" }
				)
			}

			$result = Get-PinnedApps -DataFileKey WinGetApps -VersionExcludeValue "Latest"

			$result | Should -Contain "git"
			$result | Where-Object { $_ -like "*#*" } | Should -BeNullOrEmpty
		}
	}

	Context "Reading through the overlay" {
		# No mock here: the layering is exactly what is under test, so this Context runs the real
		# Import-AppCsv over a synthetic repository.
		BeforeEach {
			$script:repoRoot = Join-Path $TestDrive "repo"
			$dataRoot = Join-Path $script:repoRoot "Windows\PowerShell\Modules\Bootstrap\Data"

			if (Test-Path -Path $script:repoRoot) {
				Remove-Item -Path $script:repoRoot -Recurse -Force
			}
			New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null

			$encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
			[System.IO.File]::WriteAllText(
				(Join-Path $dataRoot "WinGetApps.csv"),
				"App,Version,Scope,Interactive,Source,Machine`r`nBase.Pinned,1.0.0,d,n,w,All`r`nBase.Latest,Latest,d,n,w,All`r`n",
				$encoding)
			[System.IO.File]::WriteAllText(
				(Join-Path $dataRoot "WinGetApps.local.csv"),
				"App,Version,Scope,Interactive,Source,Machine`r`nBase.Latest,7.4.6,d,n,w,All`r`n-Base.Pinned,1.0.0,d,n,w,All`r`n",
				$encoding)

			$global:Configuration = @{
				BootstrapConfig = @{ DataFiles = @{ WinGetApps = 'Windows\PowerShell\Modules\Bootstrap\Data\WinGetApps.csv' } }
			}
			$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $script:repoRoot } } }
		}

		It "counts a version pinned only in the overlay, and drops one the overlay removed" {
			# The whole reason this function no longer parses the committed CSV itself. A pin that
			# lives in the machine-local overlay is invisible in the base file, and missing it would
			# let Upgrade-All upgrade straight past the pin - the exact outcome pinning prevents.
			$result = @(Get-PinnedApps -DataFileKey WinGetApps -VersionExcludeValue "Latest")

			# The overlay pinned an app the base tracked at Latest...
			$result | Should -Contain "Base.Latest"
			# ...and removed the one the base had pinned, so it is not reported as pinned any more.
			$result | Should -Not -Contain "Base.Pinned"
		}
	}
}
