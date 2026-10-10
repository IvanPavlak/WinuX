function Get-ExpectedTestCount {
	<#
	.SYNOPSIS
		Counts the tests a *.Tests.ps1 file will produce, without running Pester over it.

	.DESCRIPTION
		Invoke-TestSuite's live counter needs a denominator before the first worker has even
		finished bootstrapping. Pester 6 discovers and runs each file interleaved, so no worker
		knows its own total until it is done, and a separate discovery-only pass costs a quarter
		of the whole suite. This function reads the count off the file's syntax tree instead:
		one per It, multiplied by the element count of any literal -ForEach/-TestCases on the It
		and on every enclosing Describe/Context. Parsing all files takes about a second.

		The count is exact for every test whose case list is written into the file. An It (or
		an enclosing block) whose -ForEach is computed - a variable, a pipeline, a call - or
		that sits inside a loop or a function cannot be counted here; the file is then reported
		with Resolved = $false and Count holding only what could be counted, and the caller
		decides what to fall back to (Invoke-TestSuite uses the previous run's count for that
		file).

		Tags are read the same way. Every literal -Tag on an It, Describe or Context is reported
		in Tags, and an It that carries, or sits inside a block that carries, a tag matching
		-ExcludeTag is not counted (it is reported in Excluded instead), so that a run with
		Pester's ExcludeTag gets the right denominator. A -Tag that is computed makes the file
		unresolved when -ExcludeTag is given, because the exclusion can then not be decided.

		Deliberately a plain script beside Invoke-TestSuite rather than an exported function:
		the orchestrator dot-sources it with zero WinuX modules loaded, which is exactly the
		state CI runs it in.

	.PARAMETER Path
		Full paths of the test files to count.

	.PARAMETER ExcludeTag
		Tags (wildcards allowed, case-insensitive, like Pester's Filter.ExcludeTag) whose tests
		are left out of Count.

	.OUTPUTS
		One object per file: Path, Count (int), Resolved (bool), Excluded (int), Tags (string[]).

	.EXAMPLE
		Get-ExpectedTestCount -Path $testFiles | Measure-Object -Property Count -Sum

	.EXAMPLE
		Get-ExpectedTestCount -Path $testFiles -ExcludeTag 'Integration'
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyCollection()]
		[string[]]$Path,

		[Parameter()]
		[string[]]$ExcludeTag = @()
	)

	$blockCommands = @('Describe', 'Context')
	$ExcludeTag = @($ExcludeTag | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

	# The literal values of a -Tag argument, or $null when the argument is computed.
	$literalTags = {
		param([System.Management.Automation.Language.Ast]$Argument)
		while ($Argument -is [System.Management.Automation.Language.ParenExpressionAst] -or $Argument -is [System.Management.Automation.Language.ArrayExpressionAst]) {
			$statements = if ($Argument -is [System.Management.Automation.Language.ParenExpressionAst]) { @($Argument.Pipeline) } else { @($Argument.SubExpression.Statements) }
			if ($statements.Count -ne 1 -or $statements[0] -isnot [System.Management.Automation.Language.PipelineAst] -or $statements[0].PipelineElements.Count -ne 1 -or $statements[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) { return $null }
			$Argument = $statements[0].PipelineElements[0].Expression
		}
		$items = if ($Argument -is [System.Management.Automation.Language.ArrayLiteralAst]) { @($Argument.Elements) } else { @($Argument) }
		$values = foreach ($item in $items) {
			if ($item -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $null }
			$item.Value
		}
		return , @($values)
	}

	# The -Tag argument of an It/Describe/Context call, or $null when it has none.
	$tagArgument = {
		param([System.Management.Automation.Language.CommandAst]$Command)
		$elements = $Command.CommandElements
		for ($i = 1; $i -lt $elements.Count; $i++) {
			$element = $elements[$i]
			if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -in 'Tag', 'Tags') {
				if ($element.Argument) { return $element.Argument }
				if ($i + 1 -lt $elements.Count) { return $elements[$i + 1] }
			}
		}
		return $null
	}

	# Element count of a -ForEach argument written into the file, or $null when it is computed.
	$literalCaseCount = {
		param([System.Management.Automation.Language.Ast]$Argument)
		while ($Argument -is [System.Management.Automation.Language.ParenExpressionAst]) {
			$statements = $Argument.Pipeline.Statements
			if ($statements.Count -ne 1 -or $statements[0].PipelineElements.Count -ne 1 -or $statements[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) { return $null }
			$Argument = $statements[0].PipelineElements[0].Expression
		}
		if ($Argument -is [System.Management.Automation.Language.HashtableAst]) { return 1 }
		if ($Argument -is [System.Management.Automation.Language.ArrayLiteralAst]) { return $Argument.Elements.Count }
		if ($Argument -is [System.Management.Automation.Language.ArrayExpressionAst]) {
			$count = 0
			foreach ($statement in $Argument.SubExpression.Statements) {
				$elements = $statement.PipelineElements
				if ($statement -isnot [System.Management.Automation.Language.PipelineAst] -or $elements.Count -ne 1 -or $elements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) { return $null }
				$expression = $elements[0].Expression
				if ($expression -is [System.Management.Automation.Language.ArrayLiteralAst]) { $count += $expression.Elements.Count } else { $count += 1 }
			}
			return $count
		}
		return $null
	}

	# The -ForEach/-TestCases argument of an It/Describe/Context call, or $null when it has none.
	$forEachArgument = {
		param([System.Management.Automation.Language.CommandAst]$Command)
		$elements = $Command.CommandElements
		for ($i = 1; $i -lt $elements.Count; $i++) {
			$element = $elements[$i]
			if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -in 'ForEach', 'TestCases') {
				if ($element.Argument) { return $element.Argument }
				if ($i + 1 -lt $elements.Count) { return $elements[$i + 1] }
			}
		}
		return $null
	}

	foreach ($file in $Path) {
		$tokens = $null
		$errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)

		$count = 0
		$excluded = 0
		$resolved = $true
		$fileTags = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		$tests = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'It' }, $true)

		foreach ($block in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in 'Describe', 'Context', 'It' }, $true)) {
			$blockTag = & $tagArgument $block
			if ($blockTag) {
				$values = & $literalTags $blockTag
				foreach ($tag in @($values)) { if ($tag) { [void]$fileTags.Add([string]$tag) } }
			}
		}

		foreach ($test in $tests) {
			$cases = 1
			$argument = & $forEachArgument $test
			if ($argument) { $cases = & $literalCaseCount $argument }

			# The tags this test carries: its own plus every enclosing block's. $null once any of
			# them is computed, which only matters when there is something to exclude.
			$testTags = [System.Collections.Generic.List[string]]::new()
			$tagsKnown = $true
			$ownTag = & $tagArgument $test
			if ($ownTag) {
				$values = & $literalTags $ownTag
				if ($null -eq $values) { $tagsKnown = $false } else { $testTags.AddRange([string[]]@($values)) }
			}

			# Walk up through the enclosing blocks: a literal -ForEach on a Describe/Context
			# multiplies every It inside it; a loop or a function around the It means the file
			# decides the number at discovery time and it cannot be read off the tree.
			$multiplier = 1
			$parent = $test.Parent
			while ($parent -and $null -ne $multiplier) {
				if ($parent -is [System.Management.Automation.Language.LoopStatementAst] -or $parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
					$multiplier = $null
				}
				elseif ($parent -is [System.Management.Automation.Language.CommandAst] -and $parent.GetCommandName() -in $blockCommands) {
					$blockArgument = & $forEachArgument $parent
					if ($blockArgument) {
						$blockCases = & $literalCaseCount $blockArgument
						if ($null -eq $blockCases) { $multiplier = $null } else { $multiplier *= $blockCases }
					}
					$blockTag = & $tagArgument $parent
					if ($blockTag) {
						$values = & $literalTags $blockTag
						if ($null -eq $values) { $tagsKnown = $false } else { $testTags.AddRange([string[]]@($values)) }
					}
				}
				$parent = $parent.Parent
			}

			if ($ExcludeTag.Count -gt 0) {
				if (-not $tagsKnown) {
					$resolved = $false
					continue
				}
				$isExcluded = $false
				foreach ($tag in $testTags) {
					foreach ($pattern in $ExcludeTag) {
						if ($tag -like $pattern) { $isExcluded = $true }
					}
				}
				if ($isExcluded) {
					if ($null -ne $cases -and $null -ne $multiplier) { $excluded += $cases * $multiplier }
					continue
				}
			}

			if ($null -eq $cases -or $null -eq $multiplier) {
				$resolved = $false
				continue
			}
			$count += $cases * $multiplier
		}

		[pscustomobject]@{
			Path     = $file
			Count    = [int]$count
			Resolved = $resolved
			Excluded = [int]$excluded
			Tags     = [string[]]@($fileTags)
		}
	}
}
