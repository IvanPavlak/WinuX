#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Open-ProjectSwagger.ps1"

	# Stub dependent functions / logging so the test is self-contained
	function Resolve-SwaggerBrowserGroup { param($Project, $Browser) 'ProjectA' }
	function Open-Browser { param($Groups, $Browser) }
	function Write-LogDebug { param($Message, $Style) }
}

Describe "Open-ProjectSwagger" {
	BeforeEach {
		Mock Resolve-SwaggerBrowserGroup { 'ProjectA' }
		Mock Open-Browser {}
	}

	It "opens the resolved swagger group via Open-Browser" {
		Open-ProjectSwagger -Project 'ProjectA'

		Should -Invoke Open-Browser -Times 1 -ParameterFilter {
			@($Groups) -contains 'ProjectA'
		}
	}

	It "forwards the explicit browser to both the resolver and Open-Browser" {
		Open-ProjectSwagger -Project 'ProjectA' -Browser 'Chrome'

		Should -Invoke Resolve-SwaggerBrowserGroup -Times 1 -ParameterFilter { $Browser -eq 'Chrome' }
		Should -Invoke Open-Browser -Times 1 -ParameterFilter { $Browser -eq 'Chrome' }
	}

	It "omits the Browser parameter from Open-Browser when none is supplied" {
		Open-ProjectSwagger -Project 'ProjectA'

		Should -Invoke Open-Browser -Times 1 -ParameterFilter {
			[string]::IsNullOrEmpty($Browser)
		}
	}

	It "does not call Open-Browser when no swagger group resolves" {
		Mock Resolve-SwaggerBrowserGroup { $null }

		Open-ProjectSwagger -Project 'ProjectA'

		Should -Invoke Open-Browser -Times 0
	}

	It "silently no-ops when Project is omitted" {
		Open-ProjectSwagger

		Should -Invoke Resolve-SwaggerBrowserGroup -Times 0
		Should -Invoke Open-Browser -Times 0
	}

	It "silently no-ops for an empty project array" {
		Open-ProjectSwagger -Project @()

		Should -Invoke Resolve-SwaggerBrowserGroup -Times 0
		Should -Invoke Open-Browser -Times 0
	}

	It "silently no-ops for whitespace-only project names" {
		Open-ProjectSwagger -Project @('', '   ')

		Should -Invoke Resolve-SwaggerBrowserGroup -Times 0
		Should -Invoke Open-Browser -Times 0
	}

	It "forwards a project array to the resolver intact" {
		Open-ProjectSwagger -Project @('', 'ProjectA', 'Other')

		Should -Invoke Resolve-SwaggerBrowserGroup -Times 1 -ParameterFilter {
			@($Project).Count -eq 3 -and @($Project)[1] -eq 'ProjectA'
		}
	}
}
