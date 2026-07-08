#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-InsetWindowBounds.ps1"
}

Describe "Get-InsetWindowBounds" {
	It "returns centered inset bounds for default inset" {
		$result = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1000 -TargetHeight 800

		$result.AdjustedWidth | Should -Be 900
		$result.AdjustedHeight | Should -Be 720
		$result.AdjustedX | Should -Be 50
		$result.AdjustedY | Should -Be 40
	}

	It "enforces minimum size of 1 pixel" {
		$result = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1 -TargetHeight 1 -InsetPercent 0.49

		$result.AdjustedWidth | Should -BeGreaterOrEqual 1
		$result.AdjustedHeight | Should -BeGreaterOrEqual 1
	}
}
