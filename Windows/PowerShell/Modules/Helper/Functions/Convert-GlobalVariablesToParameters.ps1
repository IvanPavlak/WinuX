function Convert-GlobalVariablesToParameters {
	<#
    .SYNOPSIS
    Converts global variable references in a function to parameters with default values.

    .DESCRIPTION
    This function analyzes a PowerShell function definition and converts all $global:Variable
    references to regular parameters. This makes the function self-contained and suitable
    for creating standalone executables.

    .PARAMETER FunctionDefinition
    The function definition (script block or string) to process.

    .PARAMETER GlobalVariables
    Array of global variable names to convert. If not specified, all global variables
    in the function will be converted.

    .EXAMPLE
    $definition = (Get-Command Determine-DotnetDependencies).Definition
    Convert-GlobalVariablesToParameters -FunctionDefinition $definition

    Converts all global variables in the function to parameters.

    .NOTES
    The function attempts to infer appropriate default values based on common patterns.
    For example, $global:MachineSpecificPaths.DotnetProjectsSearchPath becomes a parameter
    with a default value of "$env:USERPROFILE\Development".
    #>

	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$FunctionDefinition,

		[Parameter()]
		[string[]]$GlobalVariables
	)

	$modifiedDefinition = $FunctionDefinition

	# Find all global variable references using regex
	$globalVarPattern = '\$global:([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)'
	$matches = [regex]::Matches($modifiedDefinition, $globalVarPattern)

	if ($matches.Count -eq 0) {
		# No global variables found
		return $modifiedDefinition
	}

	# Extract unique global variable paths
	$globalVarPaths = $matches | ForEach-Object {
		$_.Groups[1].Value
	} | Select-Object -Unique

	# Filter if specific variables were requested
	if ($GlobalVariables) {
		$globalVarPaths = $globalVarPaths | Where-Object {
			$baseName = ($_ -split '\.')[0]
			$GlobalVariables -contains $baseName
		}
	}

	if ($globalVarPaths.Count -eq 0) {
		return $modifiedDefinition
	}

	# Build parameter definitions and replacements
	$newParameters = @()
	$replacements = @{}

	foreach ($varPath in $globalVarPaths) {
		# Determine parameter name and default value
		$paramName = $varPath -replace '\.', ''

		# Handle specific known patterns
		$defaultValue = switch -Regex ($varPath) {
			'MachineSpecificPaths\.DotnetProjectsSearchPath' {
				'"$env:USERPROFILE\Development"'
				break
			}
			'MachineSpecificPaths\..*' {
				'$null'
				break
			}
			default {
				'$null'
			}
		}

		# Create parameter string (single line for reliability)
		$newParameters += "        [Parameter()][string]`$$paramName = $defaultValue"

		# Track replacement: $global:Path -> $paramName
		$replacements["`$global:$varPath"] = "`$$paramName"
	}

	# Use AST to properly find and modify the param block
	try {
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($modifiedDefinition, [ref]$null, [ref]$null)

		# Find the param block
		$paramBlock = $ast.FindAll({
				$args[0] -is [System.Management.Automation.Language.ParamBlockAst]
			}, $true) | Select-Object -First 1

		if ($paramBlock) {
			# Get the extent of the param block
			$paramStart = $paramBlock.Extent.StartOffset
			$paramEnd = $paramBlock.Extent.EndOffset

			# Find the last parameter's end position (before the closing paren)
			# We'll insert our new parameters just before the closing )
			$paramText = $modifiedDefinition.Substring($paramStart, $paramEnd - $paramStart)

			# Find the position of the last closing paren of the param block
			$lastParenPos = $paramText.LastIndexOf(')')

			if ($lastParenPos -gt 0) {
				# Check if there are existing parameters
				$beforeParen = $paramText.Substring(0, $lastParenPos).Trim()

				# Determine if we need a comma
				$needsComma = $beforeParen -notmatch 'param\s*\(\s*$'

				# Build the insertion text
				if ($needsComma) {
					$insertText = ",`n`n" + ($newParameters -join ",`n`n") + "`n    "
				}
				else {
					$insertText = "`n" + ($newParameters -join ",`n`n") + "`n    "
				}

				# Calculate absolute position
				$insertPosition = $paramStart + $lastParenPos

				# Insert the new parameters
				$modifiedDefinition = $modifiedDefinition.Insert($insertPosition, $insertText)
			}
		}
		else {
			# No param block found - create one
			# Find where to insert (after [CmdletBinding()] if it exists, or after function opening brace)
			$cmdletBinding = $ast.FindAll({
					$args[0] -is [System.Management.Automation.Language.AttributeAst] -and
					$args[0].TypeName.Name -eq 'CmdletBinding'
				}, $true) | Select-Object -First 1

			if ($cmdletBinding) {
				# Insert after [CmdletBinding()]
				$insertPosition = $cmdletBinding.Extent.EndOffset
				$insertText = "`n    param(`n" + ($newParameters -join ",`n`n") + "`n    )"
				$modifiedDefinition = $modifiedDefinition.Insert($insertPosition, $insertText)
			}
			else {
				# Find the function body start
				$functionDef = $ast.FindAll({
						$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
					}, $true) | Select-Object -First 1

				if ($functionDef) {
					# Insert at the start of the function body
					$insertPosition = $functionDef.Body.Extent.StartOffset + 1
					$insertText = "`n    param(`n" + ($newParameters -join ",`n`n") + "`n    )`n"
					$modifiedDefinition = $modifiedDefinition.Insert($insertPosition, $insertText)
				}
			}
		}
	}
	catch {
		Write-Warning "Failed to parse function with AST: $($_.Exception.Message)"
		return $FunctionDefinition
	}

	# Replace all global variable references with parameter references
	foreach ($pattern in $replacements.Keys) {
		$replacement = $replacements[$pattern]
		# Use simple replace for the exact pattern
		$modifiedDefinition = $modifiedDefinition.Replace($pattern, $replacement)
	}

	return $modifiedDefinition
}
