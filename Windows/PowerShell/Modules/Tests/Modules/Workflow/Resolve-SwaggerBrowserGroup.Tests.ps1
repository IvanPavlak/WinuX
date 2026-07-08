#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Resolve-SwaggerBrowserGroup.ps1"

	# Stub dependent functions / logging so the test is self-contained
	function Get-WindowHandle { param($ProcessName) @() }
	function Test-BrowserGroupAlreadyOpen { $false }
	function Write-LogDebug { param($Message, $Style) }
	function Write-LogWarning { param($Message) }
}

Describe "Resolve-SwaggerBrowserGroup" {
	BeforeEach {
		Mock Get-WindowHandle { @() }
		Mock Test-BrowserGroupAlreadyOpen { $false }

		$script:Configuration = @{
			BrowserGroups = @(
				@{ Google = @("https://google.com") }
				@{
					Swagger = @(
						@{ Name = 'ExampleProject'; Url = 'http://localhost:5287/swagger/index.html' }
						@{ Name = 'ExampleService'; Url = 'http://localhost:5999/swagger/index.html' }
					)
				}
			)
			Universal     = @{ DefaultBrowser = 'Firefox' }
		}
	}

	It "returns the swagger group name for a project that has one" {
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Should -Be 'ExampleProject'
	}

	It "matches the project name case-insensitively and returns the config-cased name" {
		Resolve-SwaggerBrowserGroup -Project 'exampleproject' | Should -Be 'ExampleProject'
	}

	It "resolves the placeholder project (problem-page fallback)" {
		Resolve-SwaggerBrowserGroup -Project 'ExampleService' | Should -Be 'ExampleService'
	}

	It "uses the first non-empty element when an array of projects is supplied" {
		Resolve-SwaggerBrowserGroup -Project @('ExampleProject', 'Other') | Should -Be 'ExampleProject'
	}

	It "returns null for a project with no swagger entry" {
		Resolve-SwaggerBrowserGroup -Project 'NoSuchProject' | Should -BeNullOrEmpty
	}

	It "returns null when no swagger parent group exists in BrowserGroups" {
		$script:Configuration.BrowserGroups = @(@{ Google = @("https://google.com") })
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Should -BeNullOrEmpty
	}

	It "returns null when the swagger tab is already open" {
		Mock Test-BrowserGroupAlreadyOpen { $true }
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Should -BeNullOrEmpty
	}

	It "runs the duplicate check by default" {
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Out-Null
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1
	}

	It "skips the duplicate check with -SkipDuplicateCheck" {
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' -SkipDuplicateCheck | Should -Be 'ExampleProject'
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 0
		Should -Invoke Get-WindowHandle -Times 0
	}

	It "forwards cached browser windows to the duplicate check without re-enumerating" {
		$cached = @([PSCustomObject]@{ Handle = [IntPtr]1; Title = 'x' })
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' -CachedBrowserWindows $cached | Out-Null
		Should -Invoke Get-WindowHandle -Times 0
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1
	}

	It "requires the Project parameter" {
		$cmd = Get-Command Resolve-SwaggerBrowserGroup
		$param = $cmd.Parameters['Project']
		$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
		$mandatoryAttr.Mandatory | Should -BeTrue
	}
}
