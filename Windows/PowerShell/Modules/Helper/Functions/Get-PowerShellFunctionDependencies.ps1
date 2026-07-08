function Get-PowerShellFunctionDependencies {
	<#
    .SYNOPSIS
    Analyzes a PowerShell function to discover its dependencies using AST (Abstract Syntax Tree).

    .DESCRIPTION
    This function parses a PowerShell function's script block to identify all commands it calls.
    It categorizes dependencies into:
    - BuiltIn: PowerShell built-in cmdlets (e.g., Get-ChildItem, Write-Host)
    - Module: Commands from external PowerShell modules
    - Custom: Commands from custom modules in the WinuX repository
    - Unknown: Commands that couldn't be resolved

    .PARAMETER FunctionName
    The name of the function to analyze.

    .PARAMETER Recursive
    If specified, recursively analyzes dependencies of custom functions.

    .EXAMPLE
    Get-PowerShellFunctionDependencies -FunctionName "Determine-DotnetDependencies"

    Analyzes the Determine-DotnetDependencies function and returns its dependencies.

    .EXAMPLE
    Get-PowerShellFunctionDependencies -FunctionName "Determine-DotnetDependencies" -Recursive

    Analyzes the function and all its custom function dependencies recursively.
    #>

	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$FunctionName,

		[Parameter()]
		[switch]$Recursive
	)

	# Track processed functions to avoid infinite loops
	if (-not $script:ProcessedFunctions) {
		$script:ProcessedFunctions = @()
	}

	# Skip if already processed
	if ($script:ProcessedFunctions -contains $FunctionName) {
		return $null
	}

	# Mark as processed
	$script:ProcessedFunctions += $FunctionName

	# Get the function command
	try {
		$command = Get-Command $FunctionName -ErrorAction Stop
	}
	catch {
		Write-Warning "Function [$FunctionName] not found!"
		return $null
	}

	# Parse the function's AST
	$AST = $command.ScriptBlock.Ast

	# Find all command calls in the function
	$commandAsts = $AST.FindAll(
		{ $args[0].GetType().Name -like 'CommandAst' },
		$true
	)

	# Extract unique command names
	$commandNames = $commandAsts | ForEach-Object {
		if ($_.CommandElements[0].Value) {
			$_.CommandElements[0].Value
		}
	} | Where-Object { $_ -ne $null } | Select-Object -Unique

	# Categorize dependencies
	$dependencies = @{
		BuiltIn         = @()
		Module          = @()
		Custom          = @()
		Unknown         = @()
		GlobalVariables = @()
	}

	# Custom modules from this repository
	$customModuleNames = @(
		"Application",
		"Bootstrap",
		"Git",
		"Helper",
		"System",
		"Workflow"
	)

	# Analyze each command
	foreach ($cmd in $commandNames) {
		# Skip the function itself
		if ($cmd -eq $FunctionName) {
			continue
		}

		$cmdInfo = Get-Command -Name $cmd -ErrorAction SilentlyContinue

		if ($cmdInfo) {
			$moduleName = $cmdInfo.Source

			if ([string]::IsNullOrEmpty($moduleName)) {
				# Built-in PowerShell cmdlet
				$dependencies.BuiltIn += $cmd
			}
			elseif ($customModuleNames -contains $moduleName) {
				# Custom function from our modules
				$customDep = [PSCustomObject]@{
					Command    = $cmd
					Module     = $moduleName
					Definition = $cmdInfo.Definition
					ScriptPath = $cmdInfo.ScriptBlock.File
				}

				$dependencies.Custom += $customDep

				# Recursively analyze custom dependencies
				if ($Recursive) {
					$nestedDeps = Get-PowerShellFunctionDependencies -FunctionName $cmd -Recursive
					if ($nestedDeps) {
						# Merge nested custom dependencies
						foreach ($nestedCustom in $nestedDeps.Custom) {
							# Add if not already in the list
							if (-not ($dependencies.Custom | Where-Object { $_.Command -eq $nestedCustom.Command })) {
								$dependencies.Custom += $nestedCustom
							}
						}
					}
				}
			}
			else {
				# External module
				$dependencies.Module += [PSCustomObject]@{
					Command = $cmd
					Module  = $moduleName
				}
			}
		}
		else {
			# Unknown command
			$dependencies.Unknown += $cmd
		}
	}

	# Find global variable references
	$variableAsts = $AST.FindAll(
		{ $args[0].GetType().Name -like 'VariableExpressionAst' },
		$true
	)

	$globalVars = $variableAsts | Where-Object {
		$_.VariablePath.UserPath -like 'global:*'
	} | ForEach-Object {
		$_.VariablePath.UserPath -replace '^global:', ''
	} | Select-Object -Unique

	$dependencies.GlobalVariables = $globalVars

	return $dependencies
}
