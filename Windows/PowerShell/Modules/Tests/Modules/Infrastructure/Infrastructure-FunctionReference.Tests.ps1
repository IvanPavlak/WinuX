#Requires -Modules Pester

Describe "Function Reference Coherence" {
	<#
	.SYNOPSIS
		Verifies the 1:1 mapping between every module's FunctionsToExport and the man-style
		entries in docs/modules/<module>.md, in both directions.

	.DESCRIPTION
		This is the hermetic CI equivalent of `List-Functions -ListDiscrepancies`. The interactive
		command compares the documentation against the functions loaded in the current session,
		which CI does not have; this test compares it against the module manifests instead - and
		since Infrastructure-ManifestCompleteness pins manifests to the files on disk in both
		directions, the three surfaces (disk, manifest, reference docs) can only agree or fail.

		Checked per engine module:
		- every FunctionsToExport entry has a `## [Name](url)` heading in docs/modules/<module>.md
		- every heading names an exported function (a leftover heading means a removal or rename
		  did not take its reference entry with it)
		- entries are alphabetical within the page, as AGENTS.md mandates

		`FunctionDiscrepancyExclusions` (Configuration.local.psd1 over the base, replacing
		wholesale like every array key) excuses documented-but-not-exported names - that is how
		`Install-Bootstrap`, a script documented on the Bootstrap page but never exported, stays
		legal. It never excuses an exported function from being documented.

		The fork-owned Custom area is checked the same way: the union of `## [Name](url)` headings
		across docs/custom/<module>.md pages must match Custom.psd1's FunctionsToExport in both
		directions. Empty on a pure-upstream setup, so that case trivially passes.
	#>

	BeforeDiscovery {
		$ExportingModules = @(
			'Application', 'Bootstrap', 'Configuration', 'Git', 'Helper',
			'Logging', 'System', 'Tests', 'Window', 'Workflow'
		)
	}

	BeforeAll {
		$RepoPaths = Get-RepositoryPath
		$ModulesRoot = $RepoPaths.Modules
		$DocsRoot = Join-Path -Path $RepoPaths.Repo -ChildPath "docs"

		# Same heading shape List-Functions parses: "## [Function-Name](url)".
		$script:HeadingPattern = '^##\s+\[(?<Name>[\w-]+)\]\('

		function Get-DocumentedFunctions([string]$PagePath) {
			if (-not (Test-Path -LiteralPath $PagePath)) { return @() }
			@(Select-String -LiteralPath $PagePath -Pattern $script:HeadingPattern |
					ForEach-Object { $_.Matches[0].Groups['Name'].Value })
		}

		# FunctionDiscrepancyExclusions with runtime merge semantics: a local value replaces the
		# base wholesale (arrays never deep-merge), an absent local key leaves the base in force.
		$baseConfig = Import-PowerShellDataFile -Path (Join-Path $RepoPaths.PowerShell "Configuration.psd1")
		$exclusions = @($baseConfig.FunctionDiscrepancyExclusions)
		$localConfigPath = Join-Path $RepoPaths.PowerShell "Configuration.local.psd1"
		if (Test-Path -LiteralPath $localConfigPath) {
			$localValue = (Import-PowerShellDataFile -Path $localConfigPath).FunctionDiscrepancyExclusions
			if ($null -ne $localValue) { $exclusions = @($localValue) }
		}
		$script:Exclusions = $exclusions
	}

	Context "Every exported function has a reference entry" {
		It "Module '<_>' documents every exported function in docs/modules" -ForEach $ExportingModules {
			$moduleName = $_
			$exported = @((Import-PowerShellDataFile -Path (Join-Path $ModulesRoot "$moduleName\$moduleName.psd1")).FunctionsToExport)
			$pagePath = Join-Path $DocsRoot "modules\$($moduleName.ToLower()).md"
			$pagePath | Should -Exist -Because "module $moduleName needs a reference page"

			$documented = Get-DocumentedFunctions $pagePath
			$missing = @($exported | Where-Object { $documented -notcontains $_ })

			$missing | Should -BeNullOrEmpty -Because "every exported function needs a man-style '## [Name](url)' entry in docs/modules/$($moduleName.ToLower()).md. Missing: $($missing -join ', ')"
		}
	}

	Context "Every reference entry names an exported function" {
		It "Module '<_>' has no orphaned reference entries" -ForEach $ExportingModules {
			$moduleName = $_
			$exported = @((Import-PowerShellDataFile -Path (Join-Path $ModulesRoot "$moduleName\$moduleName.psd1")).FunctionsToExport)
			$documented = Get-DocumentedFunctions (Join-Path $DocsRoot "modules\$($moduleName.ToLower()).md")

			$orphans = @($documented | Where-Object { ($exported -notcontains $_) -and ($script:Exclusions -notcontains $_) })

			$orphans | Should -BeNullOrEmpty -Because "a '## [Name](url)' heading must name an exported function (or a FunctionDiscrepancyExclusions entry) - a leftover here means a removal or rename did not take its docs entry with it. Orphaned: $($orphans -join ', ')"
		}
	}

	Context "Reference entries are alphabetical within their page" {
		It "Module '<_>' page lists its entries in alphabetical order" -ForEach $ExportingModules {
			$moduleName = $_
			$documented = Get-DocumentedFunctions (Join-Path $DocsRoot "modules\$($moduleName.ToLower()).md")

			$outOfOrder = @()
			for ($i = 1; $i -lt $documented.Count; $i++) {
				if ([string]::Compare($documented[$i - 1], $documented[$i], [System.StringComparison]::OrdinalIgnoreCase) -gt 0) {
					$outOfOrder += "'$($documented[$i])' belongs before '$($documented[$i - 1])'"
				}
			}

			$outOfOrder | Should -BeNullOrEmpty -Because "AGENTS.md mandates alphabetical man-style entries. $($outOfOrder -join '; ')"
		}
	}

	Context "Custom area reference matches Custom.psd1" {
		It "docs/custom pages and Custom.psd1 exports agree in both directions" {
			$customModulePath = Join-Path $ModulesRoot "Custom"
			if (-not (Test-Path -Path $customModulePath)) {
				Set-ItResult -Skipped -Because "no Custom area is present (pure-upstream setup)"
				return
			}

			$customExported = @((Import-PowerShellDataFile -Path (Join-Path $customModulePath "Custom.psd1")).FunctionsToExport)

			$customDocsPath = Join-Path $DocsRoot "custom"
			$documented = @()
			if (Test-Path -Path $customDocsPath) {
				foreach ($page in (Get-ChildItem -Path $customDocsPath -Filter "*.md" -File | Where-Object { $_.Name -ne 'README.md' })) {
					$documented += Get-DocumentedFunctions $page.FullName
				}
			}

			$missing = @($customExported | Where-Object { $documented -notcontains $_ })
			$orphans = @($documented | Where-Object { ($customExported -notcontains $_) -and ($script:Exclusions -notcontains $_) })

			$missing | Should -BeNullOrEmpty -Because "every Custom.psd1 export needs a man-style entry in a docs/custom/<module>.md page. Missing: $($missing -join ', ')"
			$orphans | Should -BeNullOrEmpty -Because "a docs/custom heading must name a Custom.psd1 export. Orphaned: $($orphans -join ', ')"
		}
	}
}
