#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Resolve-SwaggerBrowserGroup.ps1"

	# Stub dependent functions / logging so the test is self-contained
	function Get-WindowHandle { param($ProcessName) @() }
	function Test-BrowserGroupAlreadyOpen { $false }
	function Test-TcpPortReachable { param($TargetHost, $Port, $TimeoutMs) $true }
	function Write-LogDebug { param($Message, $Style) }
	function Write-LogWarning { param($Message) }
}

Describe "Resolve-SwaggerBrowserGroup" {
	BeforeEach {
		Mock Get-WindowHandle { @() }
		Mock Test-BrowserGroupAlreadyOpen { $false }
		# Backend-up default: the probe keeps the strict duplicate-check path active
		Mock Test-TcpPortReachable { $true }

		$script:Configuration = @{
			BrowserGroups        = @(
				@{ Google = @("https://google.com") }
				@{
					Swagger = @(
						@{ Name = 'ExampleProject'; Url = 'http://localhost:5287/swagger/index.html' }
						@{ Name = 'ExampleService'; Url = 'http://localhost:5999/swagger/index.html' }
					)
				}
			)
			Universal            = @{ DefaultBrowser = 'Firefox' }
			BrowserGroupMatching = @{
				Matching = @{ ProblemLoadingPagePattern = "(?i)problem.{0,10}loading.{0,10}page" }
			}
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

	It "skips the duplicate check and the backend probe with -SkipDuplicateCheck" {
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' -SkipDuplicateCheck | Should -Be 'ExampleProject'
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 0
		Should -Invoke Get-WindowHandle -Times 0
		Should -Invoke Test-TcpPortReachable -Times 0
	}

	It "forwards cached browser windows to the duplicate check without re-enumerating" {
		$cached = @([PSCustomObject]@{ Handle = [IntPtr]1; Title = 'x' })
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' -CachedBrowserWindows $cached | Out-Null
		Should -Invoke Get-WindowHandle -Times 0
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1
	}

	It "probes the swagger URL's host and port" {
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Out-Null
		Should -Invoke Test-TcpPortReachable -Times 1 -ParameterFilter {
			$TargetHost -eq 'localhost' -and $Port -eq 5287
		}
	}

	It "keeps the strict duplicate check when the backend is up" {
		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Should -Be 'ExampleProject'
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1
	}

	It "returns null when the backend is down and any failed-load window exists" {
		Mock Test-TcpPortReachable { $false }
		Mock Get-WindowHandle { @([PSCustomObject]@{ Handle = [IntPtr]1; Title = 'Problem loading page - Mozilla Firefox' }) }

		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Should -BeNullOrEmpty
	}

	It "returns the group when the backend is down but no failed-load window exists" {
		Mock Test-TcpPortReachable { $false }
		Mock Get-WindowHandle { @([PSCustomObject]@{ Handle = [IntPtr]1; Title = 'Some other tab' }) }

		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Should -Be 'ExampleProject'
	}

	It "scans cached browser windows for failed-load pages without re-enumerating" {
		Mock Test-TcpPortReachable { $false }
		$cached = @([PSCustomObject]@{ Handle = [IntPtr]1; Title = 'Problem loading page - Mozilla Firefox' })

		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' -CachedBrowserWindows $cached | Should -BeNullOrEmpty
		Should -Invoke Get-WindowHandle -Times 0
	}

	It "returns null when the backend is down and a stale loaded swagger tab matches the strict check" {
		Mock Test-TcpPortReachable { $false }
		Mock Test-BrowserGroupAlreadyOpen { $true }

		Resolve-SwaggerBrowserGroup -Project 'ExampleProject' | Should -BeNullOrEmpty
	}

	It "requires the Project parameter" {
		$cmd = Get-Command Resolve-SwaggerBrowserGroup
		$param = $cmd.Parameters['Project']
		$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
		$mandatoryAttr.Mandatory | Should -BeTrue
	}
}
