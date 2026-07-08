# ==============================================================================
# PSScriptAnalyzer settings - shared by WinuX and its forks (identical in both).
#
# SCOPE: This file drives the LINTER (VS Code "Problems" panel / Invoke-ScriptAnalyzer).
# Code FORMATTING (format-on-save) is driven separately by the powershell.codeFormatting.*
# settings in .vscode/settings.json, so the whitespace/brace/indent rules are excluded here
# (otherwise every tab-indented line would show up as a false "problem").
#
# The excludes below keep the linter GREEN on this codebase's intentional conventions, so
# what remains is real, actionable signal. Re-enable any rule by deleting its line.
# ==============================================================================
@{
	Severity     = @('Error', 'Warning')

	ExcludeRules = @(
		# --- Formatting rules: handled by the editor's formatter, not by diagnostics ---
		'PSUseConsistentIndentation'
		'PSUseConsistentWhitespace'
		'PSAlignAssignmentStatement'
		'PSPlaceOpenBrace'
		'PSPlaceCloseBrace'
		'PSUseCorrectCasing'

		# --- Intentional naming/convention choices of this codebase ---
		'PSUseApprovedVerbs'                          # Update-Repositories, Configure-*, Reload-*, ...
		'PSUseSingularNouns'                          # ...-Repositories, ...-EnvironmentVariables, ...
		'PSAvoidUsingWriteHost'                       # Write-Host is the deliberate console UX
		'PSAvoidGlobalVars'                           # $global:Configuration / $global:MachineType are the design
		'PSUseBOMForUnicodeEncodedFile'               # repo convention is UTF-8 (no BOM)
		'PSUseShouldProcessForStateChangingFunctions' # Set-*/Update-* act without -WhatIf by design

		# --- High-noise / false-positive-prone on this codebase ---
		'PSReviewUnusedParameter'                     # trips on Pester mock params, splatting, ValueFromRemainingArguments
		'PSAvoidUsingEmptyCatchBlock'                 # deliberate best-effort cleanup (e.g. log rotation)
	)
}
