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

		The fork-owned Custom area is checked the same way, but only for the pages that say they
		are a function reference. That area is sovereign - it holds whatever a fork is not ready
		to send upstream, including Agent Skills and prose guides - so the `## [Name](url)` shape
		alone cannot mean "function" there. Every docs/custom page declares its contract in an
		HTML comment (`<!-- reference: functions windows/Custom -->`, `skills`, `guide`, `none`;
		see Get-DocsReferenceMarker), and:

		- a page with no valid marker fails, so a page cannot opt itself out by omission or typo
		- pages claiming `functions windows/Custom` are checked against Custom.psd1 in both
		  directions, as before
		- a `functions` claim on an unknown windows area fails, rather than going unchecked
		- pages claiming another engine's namespace are left to that engine, which is what keeps
		  a fork of more than one upstream from having two rules fight over the same directory

		README.md is the area's landing page and declares nothing. Empty on a pure-upstream
		setup, so that case trivially passes.
	#>

	BeforeDiscovery {
		$ExportingModules = @(
			'AI', 'Application', 'Bootstrap', 'Configuration', 'Git', 'Helper',
			'Logging', 'System', 'Tests', 'Window', 'Workflow'
		)
	}

	BeforeAll {
		$RepoPaths = Get-RepositoryPath
		$ModulesRoot = $RepoPaths.Modules
		$DocsRoot = Join-Path -Path $RepoPaths.Repo -ChildPath "docs"

		# Same heading shape List-Functions parses: "## [Function-Name](url)".
		$script:HeadingPattern = '^##\s+\[(?<Name>[\w-]+)\]\('

		# The one piece of parsing this test shares with List-Functions rather than restating:
		# both must agree exactly on which sovereign pages are a function reference, and a
		# second copy of that rule is the kind of drift this whole file exists to catch. Dot-
		# sourced as a single pure function, so the test stays hermetic.
		. (Join-Path $ModulesRoot "Helper\Functions\Get-DocsReferenceMarker.ps1")

		# Sovereign areas this engine owns: marker namespace -> the manifest it binds to.
		$script:WindowsCustomNamespace = 'windows/Custom'

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

	Context "Custom area pages declare what they document" {
		It "every docs/custom page carries a valid reference marker" {
			$customDocsPath = Join-Path $DocsRoot "custom"
			if (-not (Test-Path -Path $customDocsPath)) {
				Set-ItResult -Skipped -Because "no Custom area docs are present (pure-upstream setup)"
				return
			}

			$undeclared = @()
			foreach ($page in (Get-ChildItem -Path $customDocsPath -Filter "*.md" -File | Where-Object { $_.Name -ne 'README.md' })) {
				if (-not (Get-DocsReferenceMarker -Path $page.FullName)) {
					$undeclared += $page.Name
				}
			}

			$undeclared | Should -BeNullOrEmpty -Because "the sovereign area holds functions, Agent Skills and prose alike, so a page must state which it is instead of being guessed at from its heading shape. Add one of '<!-- reference: functions windows/Custom -->', '<!-- reference: skills -->', '<!-- reference: guide -->' or '<!-- reference: none -->' (a malformed marker reads as none at all). Undeclared: $($undeclared -join ', ')"
		}

		It "no docs/custom page claims an unknown windows function area" {
			$customDocsPath = Join-Path $DocsRoot "custom"
			if (-not (Test-Path -Path $customDocsPath)) {
				Set-ItResult -Skipped -Because "no Custom area docs are present (pure-upstream setup)"
				return
			}

			$unknown = @()
			foreach ($page in (Get-ChildItem -Path $customDocsPath -Filter "*.md" -File | Where-Object { $_.Name -ne 'README.md' })) {
				$marker = Get-DocsReferenceMarker -Path $page.FullName
				if (-not $marker -or $marker.Kind -ne 'functions') { continue }
				if ($marker.Namespace -like 'windows/*' -and $marker.Namespace -ne $script:WindowsCustomNamespace) {
					$unknown += "$($page.Name) claims [$($marker.Namespace)]"
				}
			}

			$unknown | Should -BeNullOrEmpty -Because "this engine owns exactly one sovereign function manifest, so '$($script:WindowsCustomNamespace)' is the only windows namespace it can check - anything else would be a claim nobody enforces. $($unknown -join '; ')"
		}
	}

	Context "Custom area reference matches Custom.psd1" {
		It "docs/custom function pages and Custom.psd1 exports agree in both directions" {
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
					$marker = Get-DocsReferenceMarker -Path $page.FullName
					if (-not $marker -or $marker.Kind -ne 'functions' -or $marker.Namespace -ne $script:WindowsCustomNamespace) { continue }
					$documented += Get-DocumentedFunctions $page.FullName
				}
			}

			$missing = @($customExported | Where-Object { $documented -notcontains $_ })
			$orphans = @($documented | Where-Object { ($customExported -notcontains $_) -and ($script:Exclusions -notcontains $_) })

			$missing | Should -BeNullOrEmpty -Because "every Custom.psd1 export needs a man-style entry on a docs/custom page marked '<!-- reference: functions $($script:WindowsCustomNamespace) -->'. Missing: $($missing -join ', ')"
			$orphans | Should -BeNullOrEmpty -Because "a heading on a '$($script:WindowsCustomNamespace)' page must name a Custom.psd1 export - a leftover means a removal or rename did not take its docs entry with it, and an entry that is not a function at all belongs on a page marked with its own kind instead. Orphaned: $($orphans -join ', ')"
		}
	}
}
