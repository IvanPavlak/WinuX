function Get-TestImpact {
	<#
	.SYNOPSIS
		Decides which test files a set of changed paths can affect - conservatively.

	.DESCRIPTION
		The selector behind Run-Tests -Changed. Its one rule is that every test a change can affect
		still runs: when it cannot prove a test is unaffected, the test runs, and when it does not
		recognize a changed path at all, everything runs. The selection is the union of:

		1. Changed test files.
		2. Changed test fixtures (any non-test file under a test folder, e.g. Support\*.ps1,
		   MonitorFixtures.ps1, RepositoryDataSafetyFixtures.ps1): every test file that references
		   the fixture by name, transitively through fixtures that reference it. A fixture no test
		   references selects everything - its consumers cannot be seen.
		3. Changed function files (Modules\<Module>\Functions\<Name>.ps1, the Custom area included):
		   the function's own tests (<Name>*.Tests.ps1), every test file that references the
		   function, and the same for every transitive caller - a function file that references the
		   name, walked with a cycle guard (Get-TestReferenceMap reads the references).
		4. The runtime impact map, when given: every test file that executed a changed function file.
		5. The Infrastructure tests, for documentation (*.md), module manifests (which also select
		   that module's tests), and function files that were added or removed.
		6. The full suite, for what analysis cannot see the consumers of: Configuration.psd1 and
		   Configuration.local.psd1, the profile, the harness and its helper scripts,
		   RequiredPesterVersion.txt, any *.psm1 loader, the Logging module (which every test mocks),
		   *.cs sources, module Data\ files, any other file in a module folder, anything under AI\
		   except the agent prose in AI\Context and AI\Instructions, and any path no rule recognizes.

		A plain script beside Invoke-TestSuite, for the same reason as its other helpers.

	.PARAMETER ChangedPaths
		Repository-relative paths, as Get-ChangedPaths returns them.

	.PARAMETER AddedPaths
		The subset of ChangedPaths that are new.

	.PARAMETER DeletedPaths
		The subset of ChangedPaths that no longer exist.

	.PARAMETER RepositoryRoot
		The repository's top level.

	.PARAMETER PowerShellRoot
		The folder holding Configuration.psd1 and Modules\.

	.PARAMETER TestFiles
		Every test file a full run would discover (full paths). Only these can be selected.

	.PARAMETER CachePath
		The reference-map cache (Results\dependency-map.json).

	.PARAMETER ImpactMap
		Optional runtime map: function file path relative to PowerShellRoot -> the test file paths
		(same base) that executed it.

	.OUTPUTS
		[pscustomobject] FullSuite (bool), FullSuiteReasons (string[]), Files (ordered hashtable:
		full path -> string[] reasons), Notes (string[]).

	.EXAMPLE
		Get-TestImpact -ChangedPaths $changes.Paths -RepositoryRoot $changes.Root -PowerShellRoot $psRoot -TestFiles $all
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[string[]]$ChangedPaths,

		[Parameter()]
		[AllowEmptyCollection()]
		[string[]]$AddedPaths = @(),

		[Parameter()]
		[AllowEmptyCollection()]
		[string[]]$DeletedPaths = @(),

		[Parameter(Mandatory = $true)]
		[string]$RepositoryRoot,

		[Parameter(Mandatory = $true)]
		[string]$PowerShellRoot,

		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[string[]]$TestFiles,

		[Parameter()]
		[string]$CachePath,

		[Parameter()]
		[AllowNull()]
		[hashtable]$ImpactMap
	)

	$ignoreCase = [StringComparer]::OrdinalIgnoreCase
	$normalize = { param([string]$Value) ($Value -replace '\\', '/').Trim('/') }
	$repositoryRoot = (& $normalize $RepositoryRoot)
	$powerShellRoot = (& $normalize $PowerShellRoot)
	$prefix = ''
	if ($powerShellRoot.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
		$prefix = $powerShellRoot.Substring($repositoryRoot.Length).Trim('/')
	}
	$toRelative = {
		param([string]$FullPath)
		$value = & $normalize $FullPath
		if ($value.StartsWith($powerShellRoot, [StringComparison]::OrdinalIgnoreCase)) { $value = $value.Substring($powerShellRoot.Length).Trim('/') }
		$value
	}

	$modulesRoot = Join-Path -Path $PowerShellRoot -ChildPath 'Modules'
	$customRoot = Join-Path -Path $modulesRoot -ChildPath 'Custom'
	$testsRoot = Join-Path -Path $modulesRoot -ChildPath 'Tests\Modules'

	# --- What exists: function files, test files, fixtures ---

	$functionFiles = [System.Collections.Generic.List[string]]::new()
	foreach ($moduleDirectory in @(Get-ChildItem -LiteralPath $modulesRoot -Directory -ErrorAction SilentlyContinue)) {
		$functionsDirectory = Join-Path $moduleDirectory.FullName 'Functions'
		if (Test-Path -LiteralPath $functionsDirectory) {
			foreach ($file in @(Get-ChildItem -LiteralPath $functionsDirectory -Filter '*.ps1' -File)) { $functionFiles.Add($file.FullName) }
		}
	}
	$testAreaRoots = [System.Collections.Generic.List[string]]::new()
	if (Test-Path -LiteralPath $testsRoot) { $testAreaRoots.Add($testsRoot) }
	foreach ($customModule in @(Get-ChildItem -LiteralPath $customRoot -Directory -ErrorAction SilentlyContinue)) {
		$customFunctions = Join-Path $customModule.FullName 'Functions'
		if (Test-Path -LiteralPath $customFunctions) {
			foreach ($file in @(Get-ChildItem -LiteralPath $customFunctions -Filter '*.ps1' -File)) { $functionFiles.Add($file.FullName) }
		}
		$customTests = Join-Path $customModule.FullName 'Tests'
		if (Test-Path -LiteralPath $customTests) { $testAreaRoots.Add($customTests) }
	}

	$functionNames = [System.Collections.Generic.HashSet[string]]::new($ignoreCase)
	$nameOfFile = @{}
	foreach ($file in $functionFiles) {
		$name = [System.IO.Path]::GetFileNameWithoutExtension($file)
		[void]$functionNames.Add($name)
		$nameOfFile[$file] = $name
	}

	$supportFiles = @(
		foreach ($root in $testAreaRoots) {
			Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
				Where-Object { $_.Name -notlike '*.Tests.ps1' } | Select-Object -ExpandProperty FullName
		}
	)
	$supportNames = [System.Collections.Generic.HashSet[string]]::new($ignoreCase)
	foreach ($file in $supportFiles) { [void]$supportNames.Add([System.IO.Path]::GetFileNameWithoutExtension($file)) }

	# --- Classify every changed path ---

	$selected = [ordered]@{}
	$fullSuite = [System.Collections.Generic.List[string]]::new()
	$notes = [System.Collections.Generic.List[string]]::new()
	$select = {
		param([string]$File, [string]$Reason)
		if (-not $selected.Contains($File)) { $selected[$File] = [System.Collections.Generic.List[string]]::new() }
		if (-not $selected[$File].Contains($Reason)) { $selected[$File].Add($Reason) }
	}
	$selectInfrastructure = {
		param([string]$Reason)
		foreach ($file in $TestFiles) {
			if ((& $normalize $file) -like "*/Modules/Tests/Modules/Infrastructure/*") { & $select $file $Reason }
		}
	}

	$isUnder = { param([string]$Path, [string]$Root) $Path.StartsWith(((& $normalize $Root) + '/'), [StringComparison]::OrdinalIgnoreCase) }
	$testAreaNormalized = @($testAreaRoots | ForEach-Object { & $normalize $_ })
	$addedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($AddedPaths | ForEach-Object { & $normalize $_ }), $ignoreCase)
	$deletedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($DeletedPaths | ForEach-Object { & $normalize $_ }), $ignoreCase)

	$changedFunctions = [ordered]@{}
	$changedSupport = [System.Collections.Generic.List[string]]::new()

	foreach ($rawPath in $ChangedPaths) {
		$path = & $normalize $rawPath
		if (-not $path) { continue }
		$leaf = Split-Path -Path $path -Leaf
		$full = (& $normalize (Join-Path $RepositoryRoot $path))

		$inside = (-not $prefix) -or $path.StartsWith("$prefix/", [StringComparison]::OrdinalIgnoreCase)
		$inner = if ($prefix -and $inside) { $path.Substring($prefix.Length + 1) } else { $path }

		if (-not $inside) {
			# AI\Context and AI\Instructions are prose for agents; the rest of AI\ (skills, mods,
			# templates, settings) is read by the AI module, so its consumers cannot be traced.
			if (($path -like 'AI/Context/*' -or $path -like 'AI/Instructions/*') -and $leaf -like '*.md') { & $selectInfrastructure "documentation changed: $path"; continue }
			if ($path -like 'AI/*') { $fullSuite.Add("$path - the AI area is read by the AI module"); continue }
			if ($leaf -like '*.md') { & $selectInfrastructure "documentation changed: $path"; continue }
			$fullSuite.Add("$path - not recognized, so everything runs"); continue
		}

		$segments = @($inner -split '/')

		if ($inner -in 'Configuration.psd1', 'Configuration.local.psd1') { $fullSuite.Add("$path - configuration is read everywhere"); continue }
		if ($inner -in 'Microsoft.PowerShell_profile.ps1', 'profile.ps1') { $fullSuite.Add("$path - the profile"); continue }
		if ($leaf -like '*.psm1') { $fullSuite.Add("$path - a module loader"); continue }
		if ($leaf -like '*.cs') { $fullSuite.Add("$path - native source"); continue }
		if ($segments.Count -ge 2 -and $segments[0] -eq 'Modules' -and $segments[1] -eq 'Logging') { $fullSuite.Add("$path - the Logging module, which every test mocks"); continue }
		if ($segments.Count -eq 3 -and $segments[0] -eq 'Modules' -and $segments[1] -eq 'Tests' -and ($leaf -like '*.ps1' -or $leaf -eq 'RequiredPesterVersion.txt')) {
			$fullSuite.Add("$path - the test harness"); continue
		}

		# Test files and fixtures.
		$underTests = $false
		foreach ($root in $testAreaNormalized) { if (& $isUnder $full $root) { $underTests = $true } }
		if ($underTests) {
			if ($leaf -like '*.Tests.ps1') {
				$match = @($TestFiles | Where-Object { (& $normalize $_) -eq $full })
				if ($match.Count -gt 0) { & $select $match[0] 'changed' }
				elseif ($deletedSet.Contains($path)) { $notes.Add("$path was deleted - nothing to run for it") }
				continue
			}
			$changedSupport.Add([System.IO.Path]::GetFileNameWithoutExtension($leaf))
			continue
		}

		# Function files: Modules\<Module>\Functions\<Name>.ps1 and Modules\Custom\<Module>\Functions\<Name>.ps1.
		$isFunction = $leaf -like '*.ps1' -and $segments[0] -eq 'Modules' -and (
			($segments.Count -eq 4 -and $segments[2] -eq 'Functions') -or
			($segments.Count -eq 5 -and $segments[1] -eq 'Custom' -and $segments[3] -eq 'Functions'))
		if ($isFunction) {
			$name = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
			$changedFunctions[$name] = $inner
			if ($addedSet.Contains($path) -or $deletedSet.Contains($path)) {
				& $selectInfrastructure "function file added or removed: $name"
			}
			continue
		}

		# Module manifests: the Infrastructure gate, plus every test of that module.
		$isManifest = $segments.Count -eq 3 -and $segments[0] -eq 'Modules' -and $leaf -eq "$($segments[1]).psd1"
		if ($isManifest) {
			& $selectInfrastructure "module manifest changed: $path"
			$moduleName = $segments[1]
			$moduleTests = if ($moduleName -eq 'Custom') {
				@($TestFiles | Where-Object { (& $normalize $_) -like "*/Modules/Custom/*/Tests/*" })
			}
			else {
				@($TestFiles | Where-Object { (& $normalize $_) -like "*/Modules/Tests/Modules/$moduleName/*" })
			}
			foreach ($file in $moduleTests) { & $select $file "its module's manifest changed ($leaf)" }
			continue
		}

		if ($leaf -like '*.md') { & $selectInfrastructure "documentation changed: $path"; continue }

		if ($segments -contains 'Data') { $fullSuite.Add("$path - a module data file"); continue }
		$fullSuite.Add("$path - not recognized, so everything runs")
	}

	if ($fullSuite.Count -gt 0) {
		return [pscustomobject]@{ FullSuite = $true; FullSuiteReasons = [string[]]@($fullSuite); Files = $selected; Notes = [string[]]@($notes) }
	}

	if ($changedFunctions.Count -eq 0 -and $changedSupport.Count -eq 0) {
		return [pscustomobject]@{ FullSuite = $false; FullSuiteReasons = @(); Files = $selected; Notes = [string[]]@($notes) }
	}

	# --- References: who mentions which function or fixture ---

	$names = [System.Collections.Generic.HashSet[string]]::new($ignoreCase)
	foreach ($name in $functionNames) { [void]$names.Add($name) }
	foreach ($name in $supportNames) { [void]$names.Add($name) }
	foreach ($name in $changedFunctions.Keys) { [void]$names.Add($name) }
	foreach ($name in $changedSupport) { [void]$names.Add($name) }

	$scanned = @($functionFiles) + @($TestFiles) + @($supportFiles | Where-Object { $_ -like '*.ps1' })
	$references = Get-TestReferenceMap -Path $scanned -Names @($names) -RootPath $PowerShellRoot -CachePath $CachePath

	$referencedBy = @{}
	foreach ($file in $references.Keys) {
		foreach ($name in $references[$file]) {
			if (-not $referencedBy.ContainsKey($name)) { $referencedBy[$name] = [System.Collections.Generic.List[string]]::new() }
			$referencedBy[$name].Add($file)
		}
	}
	$isTest = [System.Collections.Generic.HashSet[string]]::new([string[]]@($TestFiles), $ignoreCase)
	$isSupport = [System.Collections.Generic.HashSet[string]]::new([string[]]@($supportFiles), $ignoreCase)

	# --- Functions: their own tests, their callers' tests, transitively ---

	$visited = [System.Collections.Generic.HashSet[string]]::new($ignoreCase)
	$queue = [System.Collections.Generic.Queue[object]]::new()
	foreach ($name in $changedFunctions.Keys) { $queue.Enqueue([pscustomobject]@{ Name = $name; Origin = $name; Via = $null }) }

	while ($queue.Count -gt 0) {
		$item = $queue.Dequeue()
		if (-not $visited.Add($item.Name)) { continue }

		$reasonTests = if ($item.Name -eq $item.Origin) { "tests $($item.Name)" } else { "caller of $($item.Origin) (via $($item.Name))" }
		$reasonRefs = if ($item.Name -eq $item.Origin) { "references $($item.Name)" } else { "caller of $($item.Origin) (references $($item.Name))" }

		foreach ($file in $TestFiles) {
			if ((Split-Path -Path $file -Leaf) -like "$($item.Name)*.Tests.ps1") { & $select $file $reasonTests }
		}
		foreach ($file in @($referencedBy[$item.Name])) {
			if (-not $file) { continue }
			if ($isTest.Contains($file)) { & $select $file $reasonRefs; continue }
			if ($isSupport.Contains($file)) { $changedSupport.Add([System.IO.Path]::GetFileNameWithoutExtension($file)); continue }
			$caller = $nameOfFile[$file]
			if ($caller -and -not $visited.Contains($caller)) { $queue.Enqueue([pscustomobject]@{ Name = $caller; Origin = $item.Origin; Via = $item.Name }) }
		}
	}

	# --- The runtime impact map: what actually executed the changed functions ---

	if ($ImpactMap) {
		foreach ($name in $changedFunctions.Keys) {
			$key = $changedFunctions[$name] -replace '\\', '/'
			foreach ($testRelative in @($ImpactMap[$key])) {
				if (-not $testRelative) { continue }
				$match = @($TestFiles | Where-Object { (& $toRelative $_) -eq ($testRelative -replace '\\', '/') })
				if ($match.Count -gt 0) { & $select $match[0] "executed $name at runtime (impact map)" }
			}
		}
	}

	# --- Fixtures: every test that uses them, through fixtures that use them ---

	$visitedSupport = [System.Collections.Generic.HashSet[string]]::new($ignoreCase)
	$supportQueue = [System.Collections.Generic.Queue[string]]::new()
	foreach ($name in $changedSupport) { $supportQueue.Enqueue($name) }
	while ($supportQueue.Count -gt 0) {
		$name = $supportQueue.Dequeue()
		if (-not $visitedSupport.Add($name)) { continue }
		$users = 0
		foreach ($file in @($referencedBy[$name])) {
			if (-not $file) { continue }
			if ($isTest.Contains($file)) { & $select $file "uses the fixture $name"; $users++ }
			elseif ($isSupport.Contains($file)) { $supportQueue.Enqueue([System.IO.Path]::GetFileNameWithoutExtension($file)); $users++ }
		}
		if ($users -eq 0) { $fullSuite.Add("test support file $name - no test references it, so its consumers cannot be seen") }
	}

	[pscustomobject]@{
		FullSuite        = $fullSuite.Count -gt 0
		FullSuiteReasons = [string[]]@($fullSuite)
		Files            = $selected
		Notes            = [string[]]@($notes)
	}
}
