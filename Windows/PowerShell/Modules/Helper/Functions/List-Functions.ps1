function List-Functions {
	<#
    .SYNOPSIS
        List all PowerShell functions from the docsify documentation with optional filtering.

    .DESCRIPTION
        Parses the per-module documentation pages under docs/modules/*.md - plus the fork-owned
        Custom area pages under docs/custom/*.md, when present - to extract function names,
        signatures, and descriptions. Each function is documented as a man-style entry whose
        machine-readable summary is the contiguous block of "- **Key:** value" bullets directly beneath
        its "## [FunctionName](source-url)" heading. Supports filtering by category (module), specific
        functions, or finding documentation discrepancies against the loaded session functions.

    .PARAMETER Category
        Filter to specific module category (e.g., 'Application', 'System').

    .PARAMETER Function
        Filter to specific function names.

    .PARAMETER ListDiscrepancies
        Show functions with mismatches between the documentation and actual loaded code.

    .EXAMPLE
        List-Functions -Category "System"
        List-Functions -Function "Open-Browser", "Set-Wallpaper"
        List-Functions -ListDiscrepancies
    #>
	[CmdletBinding(DefaultParameterSetName = 'ListAll')]
	param (
		[Parameter(Mandatory = $false, ParameterSetName = 'ByCategory')]
		[string[]]$Category,

		[Parameter(Mandatory = $false, ParameterSetName = 'ByFunction')]
		[string[]]$Function,

		[Parameter(Mandatory = $false, ParameterSetName = 'DiscrepancyCheck')]
		[switch]$ListDiscrepancies,

		[Parameter(Mandatory = $false, ParameterSetName = 'DiscrepancyCheck')]
		[switch]$Quiet
	)

	try {
		$projectRoot = $MachineSpecificPaths.Projects.Self.Root
		$docsRoot = $MachineSpecificPaths.Projects.Self.Docs
		if (-not $docsRoot) {
			$docsRoot = Join-Path -Path $projectRoot -ChildPath 'docs'
		}
		$modulesDocsPath = Join-Path -Path $docsRoot -ChildPath 'modules'

		if (-not (Test-Path -Path $modulesDocsPath -PathType Container)) {
			throw "Documentation modules folder not found. Looked for it at: $modulesDocsPath"
		}

		$docFiles = Get-ChildItem -Path $modulesDocsPath -Filter '*.md' -File | Sort-Object Name
		if (-not $docFiles) {
			throw "No module documentation pages (*.md) found in: $modulesDocsPath"
		}

		# Fork-owned Custom area pages (docs/custom/<module>.md) document fork-local functions
		# in the same man-style format; include them so Custom functions face the same
		# discrepancy checks. README.md is the area's landing page/template, not a module page.
		$customDocsPath = Join-Path -Path $docsRoot -ChildPath 'custom'
		if (Test-Path -Path $customDocsPath -PathType Container) {
			$docFiles += @(Get-ChildItem -Path $customDocsPath -Filter '*.md' -File |
					Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
		}
	}
	catch {
		Write-Error "Failed to locate the documentation. Please ensure docs/modules/*.md exists. Error: $_"
		return
	}

	# --- Data Parsing ---
	# Iterate each module page. Category = module name derived from the file name (application.md -> Application).
	# A function starts at a "## [Name](url)" heading; its fields are the contiguous "- **Key:** value" bullets
	# immediately beneath it (an optional run of blank lines is allowed between the heading and the first bullet).
	# The block ends at the first blank line or non-bullet line after the bullets begin, so any extended human
	# prose below is ignored by the parser.
	$moduleCategories = [ordered]@{}
	$functionToCategoryMap = @{} # Reverse lookup for finding a function's category
	$textInfo = (Get-Culture).TextInfo

	foreach ($docFile in $docFiles) {
		$currentCategory = $textInfo.ToTitleCase($docFile.BaseName)
		if (-not $moduleCategories.Contains($currentCategory)) {
			$moduleCategories[$currentCategory] = [ordered]@{}
		}

		$currentFunctionName = $null
		$blockState = 'none' # none | pending (after heading, before first bullet) | bullets (collecting) | done

		foreach ($line in (Get-Content -Path $docFile.FullName)) {
			if ($line -match '^##\s+\[(?<FunctionName>[\w-]+)\]\(') {
				$currentFunctionName = $matches['FunctionName']
				if (-not $moduleCategories[$currentCategory].Contains($currentFunctionName)) {
					$moduleCategories[$currentCategory][$currentFunctionName] = [ordered]@{}
					$functionToCategoryMap[$currentFunctionName] = $currentCategory
				}
				$blockState = 'pending'
				continue
			}

			if ($currentFunctionName -and ($blockState -eq 'pending' -or $blockState -eq 'bullets')) {
				if ($line -match '^\s*-\s*\*\*(?<Key>[^*:]+):\*\*\s*(?<Value>.*)$') {
					$key = $matches['Key'].Trim()
					$value = ($matches['Value'].Trim() -replace '`', '')
					$moduleCategories[$currentCategory][$currentFunctionName][$key] = $value
					$blockState = 'bullets'
				}
				elseif ($line.Trim() -eq '') {
					if ($blockState -eq 'bullets') { $blockState = 'done' }
					# while 'pending', blank lines between heading and first bullet are tolerated
				}
				else {
					# First non-bullet, non-blank line: extended prose begins; stop collecting fields.
					$blockState = 'done'
				}
			}
		}
	}

	$documentedFunctions = ($moduleCategories.GetEnumerator() | Where-Object { $_.Value.Count -gt 0 } | ForEach-Object { $_.Value.Keys }) | Sort-Object

	$modulesPath = $MachineSpecificPaths.Projects.Self.Modules
	$loadedFunctions = @()

	if (Test-Path -Path $modulesPath) {
		$modulesFolders = Get-ChildItem -Path $modulesPath -Directory
		foreach ($moduleFolder in $modulesFolders) {
			$moduleName = $moduleFolder.Name
			$moduleScript = Join-Path -Path $moduleFolder.FullName -ChildPath "$moduleName.psm1"

			if (Test-Path -Path $moduleScript) {
				$moduleFunctions = Get-Command -Module $moduleName -CommandType Function -ErrorAction SilentlyContinue
				if ($moduleFunctions) {
					$loadedFunctions += $moduleFunctions.Name
				}
			}
		}
	}

	if (-not $loadedFunctions) {
		$loadedFunctions = @()
	}
 else {
		$loadedFunctions = $loadedFunctions | Sort-Object -Unique
	}

	if (-not $documentedFunctions) {
		$documentedFunctions = @()
	}

	$exclusions = @()
	if ($Configuration -and $Configuration.FunctionDiscrepancyExclusions) {
		$exclusions = $Configuration.FunctionDiscrepancyExclusions
	}

	$comparison = Compare-Object -ReferenceObject $documentedFunctions -DifferenceObject $loadedFunctions -PassThru
	$missingFromSession = $comparison | Where-Object { $_.SideIndicator -eq '<=' } | Where-Object { $_ -notin $exclusions }
	$missingFromDocs = $comparison | Where-Object { $_.SideIndicator -eq '=>' }

	$discrepancyMessages = @()
	if ($missingFromSession.Count -gt 0 -or $missingFromDocs.Count -gt 0) {
		$discrepancyMessages += Create-CenteredBorder -Title "Discrepancy Report"
		if ($missingFromSession.Count -gt 0) {
			$discrepancyMessages += "`n=> The following function(s) are in the documentation but NOT loaded in the session =>`n"
			$missingFromSession | ForEach-Object { $discrepancyMessages += "    $_" }
		}
		if ($missingFromDocs.Count -gt 0) {
			$discrepancyMessages += "`n=> The following function(s) are loaded in the session but NOT in the documentation =>`n"
			$missingFromDocs | ForEach-Object { $discrepancyMessages += "    $_" }
		}
	}

	if ($PSCmdlet.ParameterSetName -eq 'DiscrepancyCheck') {
		if ($discrepancyMessages.Count -gt 0) {
			$discrepancyMessages | ForEach-Object { Write-Host -ForegroundColor $Configuration.ListFunctionsColors.DiscrepancyError $_ }
		}
		elseif (-not $Quiet) {
			# -Quiet suppresses the success banner so the profile startup check stays silent
			# when there are no discrepancies (only surfaces output when something is wrong).
			Write-Host -ForegroundColor $Configuration.ListFunctionsColors.DiscrepancySuccess "`n=> No discrepancies found between the documentation and loaded functions!"
		}
		return
	}

	Write-Host ""

	if ($PSCmdlet.ParameterSetName -eq 'ByCategory') {
		$availableCategories = $moduleCategories.Keys | Where-Object { $moduleCategories[$_].Count -gt 0 } | Sort-Object

		$resolveParams = @{
			InputObject             = $Category
			OptionList              = $availableCategories
			MenuTitle               = "[Available Categories]"
			PromptMessage           = "Enter category(s) to list by number or name"
			AllowMultipleSelections = $true
		}

		$resolvedCategories = Resolve-Selection @resolveParams

		if ($resolvedCategories) {
			foreach ($cat in $resolvedCategories) {
				$functions = $moduleCategories[$cat]
				Write-Host -ForegroundColor $Configuration.ListFunctionsColors.Border (Create-CenteredBorder -Title $cat)
				Write-Host ""
				foreach ($functionName in $functions.Keys) {
					Show-FunctionDetails -FunctionName $functionName -FunctionInfo $functions[$functionName]
				}
				Write-Host -ForegroundColor $Configuration.ListFunctionsColors.Border (Create-CenteredBorder -Title "Function count => $($functions.Count)")
				Write-Host ""
			}
		}
	}
	elseif ($PSCmdlet.ParameterSetName -eq 'ByFunction') {
		$availableFunctions = $functionToCategoryMap.Keys | Sort-Object

		$resolveParams = @{
			InputObject             = $Function
			OptionList              = $availableFunctions
			MenuTitle               = "[Available Functions]"
			PromptMessage           = "Enter function(s) to view by number or name"
			AllowMultipleSelections = $true
		}

		$resolvedFunctions = Resolve-Selection @resolveParams

		if ($resolvedFunctions) {
			foreach ($funcName in $resolvedFunctions) {
				$categoryName = $functionToCategoryMap[$funcName]
				$functionInfo = $moduleCategories[$categoryName][$funcName]
				Write-Host -ForegroundColor $Configuration.ListFunctionsColors.Border (Create-CenteredBorder -Title $categoryName)
				Write-Host ""
				Show-FunctionDetails -FunctionName $funcName -FunctionInfo $functionInfo
				Write-Host -ForegroundColor $Configuration.ListFunctionsColors.Border (Create-CenteredBorder)
				Write-Host ""
			}
		}
	}
	else {
		# Default behavior: List everything
		$totalCount = ($moduleCategories.Values | ForEach-Object { $_.Count }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
		foreach ($cat in $moduleCategories.Keys) {
			$functions = $moduleCategories[$cat]
			if ($functions.Count -gt 0) {
				Write-Host -ForegroundColor $Configuration.ListFunctionsColors.Border (Create-CenteredBorder -Title $cat)
				Write-Host ""
				foreach ($functionName in $functions.Keys) {
					Show-FunctionDetails -FunctionName $functionName -FunctionInfo $functions[$functionName]
				}
			}
		}
		Write-Host -ForegroundColor $Configuration.ListFunctionsColors.Border (Create-CenteredBorder -Title "Total function count => $totalCount")
		Write-Host ""

		if ($discrepancyMessages.Count -gt 0) {
			$discrepancyMessages | ForEach-Object { Write-Host -ForegroundColor $Configuration.ListFunctionsColors.DiscrepancyError $_ }
		}
	}
}
