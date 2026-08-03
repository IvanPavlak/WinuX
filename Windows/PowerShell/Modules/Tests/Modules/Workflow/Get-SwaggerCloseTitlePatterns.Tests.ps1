#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Get-SwaggerCloseTitlePatterns.ps1"

	# Stub logging so the test is self-contained
	function Write-LogDebug { param($Message, $Style) }
	function Test-LogVerbose { $false }
}

Describe "Get-SwaggerCloseTitlePatterns" {
	BeforeEach {
		$script:Configuration = @{
			BrowserGroups = @(
				@{ Google = @("https://google.com") }
				@{
					Swagger = @(
						@{ Name = 'LocalProject'; Url = 'http://localhost:5287/swagger/index.html' }
						@{ Name = 'LoopbackProject'; Url = 'http://127.0.0.1:5000/swagger/index.html' }
						@{ Name = 'RemoteProject'; Url = 'https://api.example.com/swagger/index.html' }
					)
				}
			)
		}
	}

	It "returns the swagger-ui and problem-page patterns for a localhost swagger project" {
		$patterns = @(Get-SwaggerCloseTitlePatterns -Project 'LocalProject')

		$patterns | Should -Contain "(?i)swagger ui"
		$patterns | Should -Contain "(?i)problem loading page"
		$patterns.Count | Should -Be 2
	}

	It "treats 127.0.0.1 as localhost" {
		$patterns = @(Get-SwaggerCloseTitlePatterns -Project 'LoopbackProject')

		$patterns | Should -Contain "(?i)problem loading page"
	}

	It "returns only the swagger-ui pattern for a non-localhost swagger URL" {
		$patterns = @(Get-SwaggerCloseTitlePatterns -Project 'RemoteProject')

		$patterns | Should -Be @("(?i)swagger ui")
	}

	It "returns nothing for a project with no swagger entry" {
		@(Get-SwaggerCloseTitlePatterns -Project 'NoSuchProject').Count | Should -Be 0
	}

	It "returns nothing when no Swagger parent group exists" {
		$script:Configuration.BrowserGroups = @(@{ Google = @("https://google.com") })

		@(Get-SwaggerCloseTitlePatterns -Project 'LocalProject').Count | Should -Be 0
	}

	It "matches the project name case-insensitively" {
		$patterns = @(Get-SwaggerCloseTitlePatterns -Project 'localproject')

		$patterns | Should -Contain "(?i)swagger ui"
	}

	It "requires the Project parameter" {
		$cmd = Get-Command Get-SwaggerCloseTitlePatterns
		$mandatoryAttr = $cmd.Parameters['Project'].Attributes |
			Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
		$mandatoryAttr.Mandatory | Should -BeTrue
	}
}
