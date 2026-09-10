#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$FunctionsPath\Get-DocsReferenceMarker.ps1"
}

Describe "Get-DocsReferenceMarker" {
	BeforeEach {
		$script:Page = Join-Path $TestDrive "page.md"
	}

	It "returns null when the file does not exist" {
		Get-DocsReferenceMarker -Path (Join-Path $TestDrive "missing.md") | Should -BeNullOrEmpty
	}

	It "returns null when the page declares no marker" {
		Set-Content -Path $script:Page -Value @("# A Page", "", "## [Some-Function](https://example.com)")

		Get-DocsReferenceMarker -Path $script:Page | Should -BeNullOrEmpty
	}

	It "reads a functions marker with its namespace" {
		Set-Content -Path $script:Page -Value @("<!-- reference: functions windows/Custom -->", "", "# AI")

		$result = Get-DocsReferenceMarker -Path $script:Page

		$result.Kind | Should -Be "functions"
		$result.Namespace | Should -Be "windows/Custom"
	}

	It "reads a namespace-less kind and reports no namespace" {
		Set-Content -Path $script:Page -Value @("<!-- reference: skills -->")

		$result = Get-DocsReferenceMarker -Path $script:Page

		$result.Kind | Should -Be "skills"
		$result.Namespace | Should -BeNullOrEmpty
	}

	It "accepts every namespace-less kind" -ForEach @("skills", "guide", "none") {
		Set-Content -Path $script:Page -Value @("<!-- reference: $_ -->")

		(Get-DocsReferenceMarker -Path $script:Page).Kind | Should -Be $_
	}

	It "accepts a marker anywhere in the page, not only the first line" {
		Set-Content -Path $script:Page -Value @("# A Page", "", "<!-- reference: guide -->", "prose")

		(Get-DocsReferenceMarker -Path $script:Page).Kind | Should -Be "guide"
	}

	It "tolerates surrounding whitespace and a lower-cases the kind" {
		Set-Content -Path $script:Page -Value @("   <!--   reference:   FUNCTIONS   unix/Workspace   -->   ")

		$result = Get-DocsReferenceMarker -Path $script:Page

		$result.Kind | Should -Be "functions"
		$result.Namespace | Should -Be "unix/Workspace"
	}

	It "returns the first well-formed marker when a page carries more than one" {
		Set-Content -Path $script:Page -Value @("<!-- reference: skills -->", "<!-- reference: guide -->")

		(Get-DocsReferenceMarker -Path $script:Page).Kind | Should -Be "skills"
	}

	# A typo must read as "undeclared" rather than as a silent opt-out, which is the whole point
	# of the marker: the coherence test fails on a null, so a malformed marker fails loudly.
	It "returns null for an unrecognized kind" {
		Set-Content -Path $script:Page -Value @("<!-- reference: functionz windows/Custom -->")

		Get-DocsReferenceMarker -Path $script:Page | Should -BeNullOrEmpty
	}

	It "returns null for a functions marker with no namespace" {
		Set-Content -Path $script:Page -Value @("<!-- reference: functions -->")

		Get-DocsReferenceMarker -Path $script:Page | Should -BeNullOrEmpty
	}

	It "returns null for a functions namespace that is not <engine>/<area>" {
		Set-Content -Path $script:Page -Value @("<!-- reference: functions Custom -->")

		Get-DocsReferenceMarker -Path $script:Page | Should -BeNullOrEmpty
	}

	It "returns null when a namespace-less kind carries a namespace anyway" {
		Set-Content -Path $script:Page -Value @("<!-- reference: skills windows/Custom -->")

		Get-DocsReferenceMarker -Path $script:Page | Should -BeNullOrEmpty
	}

	It "ignores a marker with trailing content on the same line" {
		Set-Content -Path $script:Page -Value @("<!-- reference: skills --> and then some")

		Get-DocsReferenceMarker -Path $script:Page | Should -BeNullOrEmpty
	}

	It "skips a malformed marker and reads a valid one further down" {
		Set-Content -Path $script:Page -Value @("<!-- reference: functions -->", "<!-- reference: functions windows/Custom -->")

		(Get-DocsReferenceMarker -Path $script:Page).Namespace | Should -Be "windows/Custom"
	}
}
