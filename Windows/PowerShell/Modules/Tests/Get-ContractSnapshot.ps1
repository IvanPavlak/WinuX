function Get-ContractSnapshot {
	<#
	.SYNOPSIS
		Reads the contract WinuX promises forks - its exported functions with their parameters, and
		the keys of the shipped Configuration.psd1 - into a comparable snapshot.

	.DESCRIPTION
		VERSIONING.md defines the contract as the Configuration.psd1 schema, the bootstrap contract
		and the set of exported functions. This captures the two parts a script can read:

		- Functions: every name in a module manifest's FunctionsToExport (the fork-owned Custom area
		  excluded), with the parameters its file declares - read from the syntax tree, nothing is
		  imported - each with whether it is mandatory and its [Alias()] names.
		- Aliases: every name in a manifest's AliasesToExport, so a function deprecated by an
		  alias still counts as exported.
		- ConfigurationKeys: the dotted path of every top-level key of the shipped Configuration.psd1,
		  and of every key one level inside a top-level hashtable.

		The committed baseline (ContractBaseline.json) is this snapshot taken at the last release;
		Test-ContractCompatibility compares the working tree's snapshot against it.

	.PARAMETER ModulesRoot
		The Modules folder.

	.PARAMETER ConfigurationPath
		The shipped Configuration.psd1.

	.OUTPUTS
		[System.Collections.Specialized.OrderedDictionary] with Functions, Aliases and
		ConfigurationKeys, every collection sorted so the JSON diffs cleanly.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$ModulesRoot,

		[Parameter(Mandatory = $true)]
		[string]$ConfigurationPath
	)

	$functions = [ordered]@{}
	$aliases = [System.Collections.Generic.List[string]]::new()

	$moduleDirs = Get-ChildItem -LiteralPath $ModulesRoot -Directory |
		Where-Object { $_.Name -ne 'Custom' -and (Test-Path -LiteralPath (Join-Path $_.FullName "$($_.Name).psd1")) } |
		Sort-Object Name

	$entries = [System.Collections.Generic.List[object]]::new()
	foreach ($moduleDir in $moduleDirs) {
		$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleDir.FullName "$($moduleDir.Name).psd1")
		foreach ($name in @($manifest.FunctionsToExport)) {
			if ($name -and $name -ne '*') { $entries.Add([pscustomobject]@{ Module = $moduleDir.Name; Name = [string]$name; Dir = $moduleDir.FullName }) }
		}
		foreach ($alias in @($manifest.AliasesToExport)) {
			if ($alias -and $alias -ne '*') { $aliases.Add([string]$alias) }
		}
	}

	foreach ($entry in ($entries | Sort-Object Name)) {
		$parameters = [ordered]@{}
		$file = Join-Path $entry.Dir "Functions\$($entry.Name).ps1"
		if (Test-Path -LiteralPath $file) {
			$ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
			$definition = $ast.Find({
					param($node)
					$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $entry.Name
				}, $true)
			if ($definition) {
				$parameterAsts = if ($definition.Body.ParamBlock) { $definition.Body.ParamBlock.Parameters } else { $definition.Parameters }
				foreach ($parameterAst in (@($parameterAsts) | Where-Object { $_ } | Sort-Object { $_.Name.VariablePath.UserPath })) {
					$mandatory = $false
					$parameterAliases = [System.Collections.Generic.List[string]]::new()
					foreach ($attribute in $parameterAst.Attributes) {
						if ($attribute -isnot [System.Management.Automation.Language.AttributeAst]) { continue }
						if ($attribute.TypeName.Name -in 'Parameter', 'System.Management.Automation.ParameterAttribute') {
							foreach ($named in $attribute.NamedArguments) {
								if ($named.ArgumentName -eq 'Mandatory') {
									$mandatory = if ($named.ExpressionOmitted) { $true } else { [bool]$named.Argument.SafeGetValue() }
								}
							}
						}
						elseif ($attribute.TypeName.Name -in 'Alias', 'System.Management.Automation.AliasAttribute') {
							foreach ($positional in $attribute.PositionalArguments) {
								foreach ($value in @($positional.SafeGetValue())) { $parameterAliases.Add([string]$value) }
							}
						}
					}
					$parameters[$parameterAst.Name.VariablePath.UserPath] = [ordered]@{
						Mandatory = $mandatory
						Aliases   = @($parameterAliases | Sort-Object)
					}
				}
			}
		}
		$functions[$entry.Name] = [ordered]@{ Module = $entry.Module; Parameters = $parameters }
	}

	$configuration = Import-PowerShellDataFile -LiteralPath $ConfigurationPath
	$keys = [System.Collections.Generic.List[string]]::new()
	foreach ($key in $configuration.Keys) {
		$keys.Add([string]$key)
		if ($configuration[$key] -is [hashtable]) {
			foreach ($child in $configuration[$key].Keys) { $keys.Add("$key.$child") }
		}
	}

	return [ordered]@{
		Functions         = $functions
		Aliases           = @($aliases | Sort-Object -Unique)
		ConfigurationKeys = @($keys | Sort-Object -Unique)
	}
}
