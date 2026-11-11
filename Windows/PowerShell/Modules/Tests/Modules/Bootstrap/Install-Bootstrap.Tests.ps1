#Requires -Modules Pester

# Install-Bootstrap.ps1 runs Install-Bootstrap as soon as it is loaded, so it is never dot-sourced
# here: these tests read the parsed script instead.

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$script:ScriptPath = Join-Path $ModuleRoot "Bootstrap\Install-Bootstrap.ps1"
	$script:CsvPath = Join-Path $ModuleRoot "Bootstrap\Data\WinGetApps.csv"

	$tokens = $null
	$parseErrors = $null
	$script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$parseErrors)
	$script:ParseErrors = $parseErrors

	# The value of the script-level $PinnedPowerShellVersion assignment.
	$assignment = $script:Ast.EndBlock.Statements |
		Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.VariablePath.UserPath -eq 'PinnedPowerShellVersion' } |
		Select-Object -First 1
	$script:PinnedVersion = if ($assignment) { $assignment.Right.Expression.Value } else { $null }

	# The Microsoft.PowerShell row of the committed app list (comments and the header skipped).
	$script:CsvRow = Get-Content -LiteralPath $script:CsvPath |
		Where-Object { $_ -match '^Microsoft\.PowerShell,' } |
		Select-Object -First 1

	$script:InstallPowerShell = $script:Ast.Find({
			param($node)
			$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-PowerShell'
		}, $false)
}

Describe "Install-Bootstrap.ps1" {
	It "parses without errors" {
		$script:ParseErrors | Should -BeNullOrEmpty
	}

	Context "the PowerShell version of the first run" {
		It "is pinned to a specific version, not Latest" {
			$script:PinnedVersion | Should -Match '^\d+(\.\d+){1,3}$'
		}

		It "is the version the committed WinGetApps.csv pins, so the app list never adds a second install" {
			$script:CsvRow | Should -Not -BeNullOrEmpty
			($script:CsvRow -split ',')[1] | Should -Be $script:PinnedVersion
		}

		It "is what Install-PowerShell passes to winget, by exact id" {
			$script:InstallPowerShell | Should -Not -BeNullOrEmpty
			$body = $script:InstallPowerShell.Body.Extent.Text

			$body | Should -Match 'winget install --id Microsoft\.PowerShell --exact --version \$PinnedPowerShellVersion'
			$body | Should -Not -Match 'winget install Microsoft\.PowerShell '
		}
	}
}
