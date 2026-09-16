#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\System\Functions\Test-FastfetchPanelOverflow.ps1"
}

Describe "Test-FastfetchPanelOverflow" {
	It "fits when the panel is narrower and leaves the cursor row plus the prompt reserve free" {
		Test-FastfetchPanelOverflow -PanelWidth 100 -PanelHeight 28 -WindowWidth 120 -WindowHeight 30 | Should -BeFalse
	}

	It "overflows when the panel is wider than the window" {
		Test-FastfetchPanelOverflow -PanelWidth 121 -PanelHeight 10 -WindowWidth 120 -WindowHeight 30 | Should -BeTrue
	}

	It "overflows when the panel leaves no room for the cursor row and the prompt" {
		Test-FastfetchPanelOverflow -PanelWidth 100 -PanelHeight 29 -WindowWidth 120 -WindowHeight 30 | Should -BeTrue
	}

	It "overflows when both dimensions are too large" {
		Test-FastfetchPanelOverflow -PanelWidth 200 -PanelHeight 60 -WindowWidth 120 -WindowHeight 30 | Should -BeTrue
	}

	It "treats a panel exactly as wide as the window as fitting" {
		Test-FastfetchPanelOverflow -PanelWidth 120 -PanelHeight 10 -WindowWidth 120 -WindowHeight 30 | Should -BeFalse
	}

	It "reserves -PromptReserve rows below the panel" {
		Test-FastfetchPanelOverflow -PanelWidth 100 -PanelHeight 27 -WindowWidth 120 -WindowHeight 30 -PromptReserve 2 | Should -BeFalse
		Test-FastfetchPanelOverflow -PanelWidth 100 -PanelHeight 28 -WindowWidth 120 -WindowHeight 30 -PromptReserve 2 | Should -BeTrue
	}

	It "with -PromptReserve 0 still keeps the cursor row free" {
		Test-FastfetchPanelOverflow -PanelWidth 100 -PanelHeight 29 -WindowWidth 120 -WindowHeight 30 -PromptReserve 0 | Should -BeFalse
		Test-FastfetchPanelOverflow -PanelWidth 100 -PanelHeight 30 -WindowWidth 120 -WindowHeight 30 -PromptReserve 0 | Should -BeTrue
	}

	It "treats an empty panel as fitting any window" {
		Test-FastfetchPanelOverflow -PanelWidth 0 -PanelHeight 0 -WindowWidth 1 -WindowHeight 2 | Should -BeFalse
	}

	It "returns a boolean" {
		Test-FastfetchPanelOverflow -PanelWidth 1 -PanelHeight 1 -WindowWidth 10 -WindowHeight 10 | Should -BeOfType [bool]
	}
}
