#Requires -Modules Pester

Describe "Configuration Guide Coverage" {
	<#
	.SYNOPSIS
		Verifies the 1:1 mapping between every module's FunctionsToExport and the per-function
		configuration guides under docs/configuration/guides/<module>/.

	.DESCRIPTION
		Every exported function has exactly one guide file named after it, in the folder of its
		module. Both directions are checked: an exported function with no guide fails, and a guide
		file that matches no exported function fails (which is what catches a rename that moved the
		function but left the old guide behind).

		The 7 task guides (lowercase, hyphenated filenames such as add-new-machine.md) and each
		module's README.md index are excluded from the second direction - they are pages about a
		task, not about one function.

		A guide is also checked for the shape its template demands: a stub carries the verbatim
		sentinel sentence and no Decisions section, and a full guide carries all of the mandatory
		headings that winux-configurator.md parses.
	#>

	BeforeDiscovery {
		# -ForEach binds at discovery time, before any BeforeAll runs, so this list is built here.
		$ExportingModules = @(
			'Application', 'Bootstrap', 'Configuration', 'Git', 'Helper',
			'Logging', 'System', 'Tests', 'Window', 'Workflow'
		)
	}

	BeforeAll {
		$RepoPaths = Get-RepositoryPath
		$ModulesRoot = $RepoPaths.Modules
		$GuidesRoot = Join-Path -Path $RepoPaths.Repo -ChildPath "docs\configuration\guides"

		# Pages about a task rather than about one function. They live in the module folder they
		# belong to, so they have to be excluded from the guide-to-function direction.
		$TaskGuideFiles = @(
			'add-browser-group.md', 'add-new-machine.md', 'add-new-project.md',
			'add-new-repository.md', 'add-new-workspace.md', 'add-symbolic-link.md',
			'configure-window-layout.md'
		)

		# Verbatim mandatory. Changing this string means changing every stub guide and
		# AI/Instructions/DocumentationStyle.md in the same commit.
		$StubSentinel = 'This function reads no `Configuration.psd1` keys. There is nothing to configure.'

		$FullHeadings = @(
			'## Configuration Keys', '## Decisions', '## Where to Put Values',
			'## Steps Overview', '## Verification', '## Complete Example', '## Related'
		)
	}

	Context "Guides root exists" {
		It "Has a guides directory" {
			$GuidesRoot | Should -Exist -Because "the per-function configuration guides live under docs/configuration/guides/"
		}
	}

	Context "Every exported function has exactly one guide" {
		It "Module '<_>' has a guide for every exported function" -ForEach $ExportingModules {
			$moduleName = $_
			$manifestPath = Join-Path -Path $ModulesRoot -ChildPath "$moduleName\$moduleName.psd1"
			$manifestPath | Should -Exist -Because "manifest must exist for module $moduleName"

			$moduleGuideDir = Join-Path -Path $GuidesRoot -ChildPath $moduleName.ToLower()
			$moduleGuideDir | Should -Exist -Because "module $moduleName must have a guides folder"

			$exported = @((Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport)
			$missing = @()
			foreach ($fn in $exported) {
				if (-not (Test-Path -LiteralPath (Join-Path -Path $moduleGuideDir -ChildPath "$fn.md"))) {
					$missing += $fn
				}
			}

			$missing | Should -BeNullOrEmpty -Because "every exported function needs docs/configuration/guides/$($moduleName.ToLower())/<Name>.md. Missing: $($missing -join ', ')"
		}

		It "Module '<_>' has an index page" -ForEach $ExportingModules {
			$indexPath = Join-Path -Path $GuidesRoot -ChildPath "$($_.ToLower())\README.md"
			$indexPath | Should -Exist -Because "each module's guides folder needs a README.md index - it is the only inbound link most guides have"
		}
	}

	Context "Every guide corresponds to an exported function" {
		It "Module '<_>' has no orphaned guide files" -ForEach $ExportingModules {
			$moduleName = $_
			$moduleGuideDir = Join-Path -Path $GuidesRoot -ChildPath $moduleName.ToLower()
			$exported = @((Import-PowerShellDataFile -Path (Join-Path -Path $ModulesRoot -ChildPath "$moduleName\$moduleName.psd1")).FunctionsToExport)

			$orphans = @()
			foreach ($file in (Get-ChildItem -Path $moduleGuideDir -Filter "*.md")) {
				if ($file.Name -eq 'README.md') { continue }
				if ($TaskGuideFiles -contains $file.Name) { continue }
				if ($exported -notcontains $file.BaseName) { $orphans += $file.Name }
			}

			$orphans | Should -BeNullOrEmpty -Because "a guide file must name an exported function - a leftover here means a rename or removal did not take its guide with it. Orphaned: $($orphans -join ', ')"
		}
	}

	Context "Every guide follows its template" {
		It "Module '<_>' guides carry the headings their template requires" -ForEach $ExportingModules {
			$moduleName = $_
			$moduleGuideDir = Join-Path -Path $GuidesRoot -ChildPath $moduleName.ToLower()

			$problems = @()
			foreach ($file in (Get-ChildItem -Path $moduleGuideDir -Filter "*.md")) {
				if ($file.Name -eq 'README.md') { continue }
				if ($TaskGuideFiles -contains $file.Name) { continue }

				$content = Get-Content -LiteralPath $file.FullName -Raw

				if ($content.Contains($StubSentinel)) {
					# Stub: sentinel, Usage, Related - and no Decisions, which would mean it is
					# really a full guide that kept the sentinel by mistake.
					foreach ($heading in @('## Configuration Keys', '## Usage', '## Related')) {
						if ($content -notmatch "(?m)^$([regex]::Escape($heading))\s*$") {
							$problems += "$($file.Name): stub is missing '$heading'"
						}
					}
					if ($content -match '(?m)^## Decisions\s*$') {
						$problems += "$($file.Name): carries the stub sentinel and a Decisions section - upgrade it to the full template or drop the sentinel"
					}
				}
				else {
					foreach ($heading in $FullHeadings) {
						if ($content -notmatch "(?m)^$([regex]::Escape($heading))\s*$") {
							$problems += "$($file.Name): full guide is missing '$heading'"
						}
					}
					if ($content -notmatch '(?m)^## Step \d+: ') {
						$problems += "$($file.Name): full guide has no '## Step N: <Title>' heading"
					}
				}
			}

			$problems | Should -BeNullOrEmpty -Because "guides follow the templates in AI/Instructions/DocumentationStyle.md. Problems: $($problems -join '; ')"
		}
	}

	Context "The configurator page exists and is registered" {
		It "winux-configurator.md exists" {
			$configurator = Join-Path -Path $RepoPaths.Repo -ChildPath "docs\configuration\winux-configurator.md"
			$configurator | Should -Exist -Because "the guides link to it from every page"
		}

		It "The sidebar lists all ten module index pages" {
			$sidebar = Get-Content -LiteralPath (Join-Path -Path $RepoPaths.Repo -ChildPath "docs\_sidebar.md") -Raw
			$missing = @()
			foreach ($m in @('application', 'bootstrap', 'configuration', 'git', 'helper', 'logging', 'system', 'tests', 'window', 'workflow')) {
				if ($sidebar -notmatch [regex]::Escape("/configuration/guides/$m/README.md")) { $missing += $m }
			}
			$missing | Should -BeNullOrEmpty -Because "the module index pages are the sidebar's entry point into the guides. Missing: $($missing -join ', ')"
		}
	}
}
