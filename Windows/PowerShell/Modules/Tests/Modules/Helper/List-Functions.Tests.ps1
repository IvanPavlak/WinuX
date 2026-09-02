#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\List-Functions.ps1"
}

Describe "List-Functions" {
	BeforeEach {
		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self    = [PSCustomObject]@{
					Root = "C:\\MissingRoot"
				}
				Modules = "C:\\MissingModules"
			}
		}

		Mock Test-Path { $false }
		Mock Write-Error { }
	}

	It "reports an error and returns when the documentation cannot be found" {
		{ List-Functions } | Should -Not -Throw
		Should -Invoke Write-Error -Times 1
	}
}

Describe "List-Functions -ListDiscrepancies" {
	BeforeAll {
		# A throwaway docs tree and a throwaway module, so the comparison has something real on both
		# sides: FakeArea exports two functions, and the page documents one of them plus one that
		# does not exist. That is exactly one discrepancy in each direction.
		$script:FixtureRoot = Join-Path $TestDrive "Fixture"
		$script:DocsRoot = Join-Path $script:FixtureRoot "docs"
		$script:ModulesRoot = Join-Path $script:FixtureRoot "Modules"
		$moduleDir = Join-Path $script:ModulesRoot "FakeArea"

		New-Item -ItemType Directory -Path (Join-Path $script:DocsRoot "modules") -Force | Out-Null
		New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null

		Set-Content -LiteralPath (Join-Path $moduleDir "FakeArea.psm1") -Value @(
			'function Get-FakeDocumented { "documented" }'
			'function Get-FakeUndocumented { "undocumented" }'
			'Export-ModuleMember -Function Get-FakeDocumented, Get-FakeUndocumented'
		)

		Set-Content -LiteralPath (Join-Path $script:DocsRoot "modules\fakearea.md") -Value @(
			'# FakeArea Module'
			''
			'## [Get-FakeDocumented](https://example.invalid/Get-FakeDocumented.ps1)'
			''
			'- **Description:** Exported and documented, so never a discrepancy.'
			''
			'## [Get-FakeNeverLoaded](https://example.invalid/Get-FakeNeverLoaded.ps1)'
			''
			'- **Description:** Documented but not exported, like a standalone script.'
			''
			'## [Get-FakeShadowed](https://example.invalid/Get-FakeShadowed.ps1)'
			''
			'- **Description:** Documented, and resolvable in the session, but redefined in global scope'
			'  so its module no longer reports it - what the profile does to Initialize-OhMyPosh.'
			''
		)

		# The global redefinition. FakeArea never exports it, so Get-Command -Module FakeArea
		# cannot see it, but Get-Command by name can - exactly like a profile dot-source.
		New-Item -Path function:global:Get-FakeShadowed -Value { "shadowed" } -Force | Out-Null

		Import-Module (Join-Path $moduleDir "FakeArea.psm1") -Force -Global
	}

	AfterAll {
		Remove-Module FakeArea -Force -ErrorAction SilentlyContinue
		Remove-Item -Path function:global:Get-FakeShadowed -Force -ErrorAction SilentlyContinue
	}

	BeforeEach {
		# Root, Docs and Modules all live under Projects.Self - that is the shape
		# List-Functions reads (Projects.Self.Modules, not Projects.Modules).
		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{
					Root    = $script:FixtureRoot
					Docs    = $script:DocsRoot
					Modules = $script:ModulesRoot
				}
			}
		}

		$script:Reported = [Collections.Generic.List[string]]::new()
		Mock Write-Host { if ($null -ne $Object) { $script:Reported.Add([string]$Object) } }
	}

	It "reports a discrepancy in each direction when nothing is excluded" {
		$script:Configuration = @{
			FunctionDiscrepancyExclusions = @()
			ListFunctionsColors           = @{ DiscrepancyError = "Red"; DiscrepancySuccess = "Green"; Border = "DarkCyan" }
		}

		List-Functions -ListDiscrepancies

		$output = $script:Reported -join "`n"
		$output | Should -Match "Get-FakeNeverLoaded"    # documented, not loaded
		$output | Should -Match "Get-FakeUndocumented"   # loaded, not documented
		$output | Should -Not -Match "No discrepancies"
	}

	It "treats a documented function as loaded when it resolves, even if its module cannot see it" {
		# The profile redefines a few module functions in global scope so their effects land in the
		# caller's scope (Initialize-OhMyPosh, Test-PowerPlan). The global copy carries no module
		# attribution, so the per-module enumeration stops reporting it and the function looked
		# absent from a session that had it loaded the whole time. Resolving by name fixes that
		# without needing an exclusion entry per shadowed function.
		$script:Configuration = @{
			FunctionDiscrepancyExclusions = @()
			ListFunctionsColors           = @{ DiscrepancyError = "Red"; DiscrepancySuccess = "Green"; Border = "DarkCyan" }
		}

		List-Functions -ListDiscrepancies

		($script:Reported -join "`n") | Should -Not -Match "Get-FakeShadowed"
	}

	It "still reports a documented function that resolves nowhere at all" {
		# The guard the resolve-by-name check must not weaken.
		$script:Configuration = @{
			FunctionDiscrepancyExclusions = @()
			ListFunctionsColors           = @{ DiscrepancyError = "Red"; DiscrepancySuccess = "Green"; Border = "DarkCyan" }
		}

		List-Functions -ListDiscrepancies

		($script:Reported -join "`n") | Should -Match "Get-FakeNeverLoaded"
	}

	It "honours the exclusion list in the documented-but-not-loaded direction" {
		$script:Configuration = @{
			FunctionDiscrepancyExclusions = @("Get-FakeNeverLoaded")
			ListFunctionsColors           = @{ DiscrepancyError = "Red"; DiscrepancySuccess = "Green"; Border = "DarkCyan" }
		}

		List-Functions -ListDiscrepancies

		$output = $script:Reported -join "`n"
		$output | Should -Not -Match "Get-FakeNeverLoaded"
		$output | Should -Match "Get-FakeUndocumented"
	}

	It "honours the exclusion list in the loaded-but-not-documented direction" {
		# The direction the profile chain produces, and the one the exclusion list used to ignore.
		# Reload-PowerShellProfile dot-sources that chain from inside the System module, and
		# PowerShell stamps the defining module onto every function created during the call - even
		# one declared global: - so a profile-defined helper such as the all-hosts profile's
		# `fastfetch` wrapper starts reporting as an undocumented System export after a reload.
		$script:Configuration = @{
			FunctionDiscrepancyExclusions = @("Get-FakeUndocumented")
			ListFunctionsColors           = @{ DiscrepancyError = "Red"; DiscrepancySuccess = "Green"; Border = "DarkCyan" }
		}

		List-Functions -ListDiscrepancies

		$output = $script:Reported -join "`n"
		$output | Should -Not -Match "Get-FakeUndocumented"
		$output | Should -Match "Get-FakeNeverLoaded"
	}

	It "reports no discrepancies when both remaining directions are excluded" {
		$script:Configuration = @{
			FunctionDiscrepancyExclusions = @("Get-FakeNeverLoaded", "Get-FakeUndocumented")
			ListFunctionsColors           = @{ DiscrepancyError = "Red"; DiscrepancySuccess = "Green"; Border = "DarkCyan" }
		}

		List-Functions -ListDiscrepancies

		($script:Reported -join "`n") | Should -Match "No discrepancies"
	}

	It "stays silent with -Quiet when there is nothing to report" {
		# The profile startup check runs this way: output only when something is actually wrong.
		$script:Configuration = @{
			FunctionDiscrepancyExclusions = @("Get-FakeNeverLoaded", "Get-FakeUndocumented")
			ListFunctionsColors           = @{ DiscrepancyError = "Red"; DiscrepancySuccess = "Green"; Border = "DarkCyan" }
		}

		List-Functions -ListDiscrepancies -Quiet

		($script:Reported -join "`n") | Should -Not -Match "No discrepancies"
	}
}
