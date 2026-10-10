#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Tests\Get-TestReferenceMap.ps1")
	. (Join-Path $ModuleRoot "Tests\Get-TestImpact.ps1")

	# A miniature repository with the same layout as the real one: two modules, their tests, two
	# fixtures, an Infrastructure test, and call chains to walk. Only the files' tokens matter -
	# nothing here is ever run.
	$script:Repo = Join-Path $TestDrive 'repo'
	$script:PowerShellRoot = Join-Path $script:Repo 'Windows\PowerShell'
	$files = [ordered]@{
		'Windows\PowerShell\Configuration.psd1'                                   = '@{}'
		'Windows\PowerShell\Modules\Alpha\Alpha.psd1'                              = '@{ FunctionsToExport = @() }'
		'Windows\PowerShell\Modules\Alpha\Alpha.psm1'                              = '# loader'
		'Windows\PowerShell\Modules\Alpha\Functions\Get-Leaf.ps1'                  = 'function Get-Leaf { "leaf" }'
		'Windows\PowerShell\Modules\Alpha\Functions\Invoke-Middle.ps1'             = 'function Invoke-Middle { Get-Leaf }'
		'Windows\PowerShell\Modules\Beta\Functions\Start-Top.ps1'                  = 'function Start-Top { Invoke-Middle }'
		'Windows\PowerShell\Modules\Beta\Functions\Use-ByString.ps1'               = 'function Use-ByString { $name = ''Get-Leaf''; & $name }'
		'Windows\PowerShell\Modules\Beta\Functions\Ping-A.ps1'                     = 'function Ping-A { Ping-B }'
		'Windows\PowerShell\Modules\Beta\Functions\Ping-B.ps1'                     = 'function Ping-B { Ping-A }'
		'Windows\PowerShell\Modules\Beta\Functions\Only-Comments.ps1'              = "function Only-Comments {`n`t# Get-Leaf is mentioned here only`n}"
		'Windows\PowerShell\Modules\Tests\Modules\Alpha\Get-Leaf.Tests.ps1'        = 'Describe "x" { It "y" { Get-Leaf } }'
		'Windows\PowerShell\Modules\Tests\Modules\Alpha\Invoke-Middle.Tests.ps1'   = 'Describe "x" { It "y" { Invoke-Middle } }'
		'Windows\PowerShell\Modules\Tests\Modules\Beta\Start-Top.Tests.ps1'        = 'Describe "x" { It "y" { Start-Top } }'
		'Windows\PowerShell\Modules\Tests\Modules\Beta\Use-ByString.Tests.ps1'     = 'Describe "x" { It "y" { Use-ByString } }'
		'Windows\PowerShell\Modules\Tests\Modules\Beta\Ping-B.Tests.ps1'           = 'Describe "x" { It "y" { Ping-B } }'
		'Windows\PowerShell\Modules\Tests\Modules\Beta\Unrelated.Tests.ps1'        = 'Describe "x" { It "y" { 1 | Should -Be 1 } }'
		'Windows\PowerShell\Modules\Tests\Modules\Beta\Comment.Tests.ps1'          = "Describe 'x' {`n`t# Get-Leaf`n`tIt 'y' { }`n}"
		'Windows\PowerShell\Modules\Tests\Modules\Beta\Folder.Tests.ps1'           = 'BeforeAll { . "$root\Get-Leaf\Functions\Something.ps1" }'
		'Windows\PowerShell\Modules\Tests\Modules\Beta\Uses-Fake.Tests.ps1'        = 'BeforeAll { . (Join-Path $PSScriptRoot "..\Support\FakeThing.ps1") }'
		'Windows\PowerShell\Modules\Tests\Modules\Support\FakeThing.ps1'           = 'function New-FakeThing { }'
		'Windows\PowerShell\Modules\Tests\Modules\Support\Orphan.ps1'              = 'function New-Orphan { }'
		'Windows\PowerShell\Modules\Tests\Modules\Infrastructure\Infrastructure-Docs.Tests.ps1' = 'Describe "docs" { }'
	}
	foreach ($relative in $files.Keys) {
		$path = Join-Path $script:Repo $relative
		New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
		Set-Content -LiteralPath $path -Value $files[$relative] -Encoding UTF8
	}
	$script:TestFiles = @(Get-ChildItem -Path (Join-Path $script:PowerShellRoot 'Modules') -Recurse -Filter '*.Tests.ps1' -File | Select-Object -ExpandProperty FullName)

	# Leaf names of the selected files.
	function Get-Selected {
		param([string[]]$ChangedPaths, [string[]]$AddedPaths = @(), [string[]]$DeletedPaths = @(), [hashtable]$ImpactMap)
		$result = Get-TestImpact -ChangedPaths $ChangedPaths -AddedPaths $AddedPaths -DeletedPaths $DeletedPaths -RepositoryRoot $script:Repo `
			-PowerShellRoot $script:PowerShellRoot -TestFiles $script:TestFiles -ImpactMap $ImpactMap
		[pscustomobject]@{
			Result = $result
			Names  = @($result.Files.Keys | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
		}
	}
}

Describe "Get-TestImpact" {
	Context "A changed function" {
		BeforeAll {
			$script:LeafChange = Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Alpha/Functions/Get-Leaf.ps1'
		}

		It "selects the function's own tests" {
			$script:LeafChange.Names | Should -Contain 'Get-Leaf.Tests.ps1'
			$script:LeafChange.Result.FullSuite | Should -BeFalse
		}

		It "selects the tests of a direct caller and of a transitive caller" {
			$script:LeafChange.Names | Should -Contain 'Invoke-Middle.Tests.ps1'
			$script:LeafChange.Names | Should -Contain 'Start-Top.Tests.ps1'
		}

		It "counts a call through a name written as a string literal" {
			$script:LeafChange.Names | Should -Contain 'Use-ByString.Tests.ps1'
		}

		It "ignores mentions in comments and folder names in paths" {
			$script:LeafChange.Names | Should -Not -Contain 'Comment.Tests.ps1'
			$script:LeafChange.Names | Should -Not -Contain 'Folder.Tests.ps1'
			$script:LeafChange.Names | Should -Not -Contain 'Unrelated.Tests.ps1'
		}

		It "says why each file was picked" {
			$middle = $script:LeafChange.Result.Files.Keys | Where-Object { $_ -like '*Invoke-Middle.Tests.ps1' }
			($script:LeafChange.Result.Files[$middle] -join ';') | Should -Match 'caller of Get-Leaf'
		}

		It "terminates on a call cycle and still selects both sides" {
			$selection = Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Beta/Functions/Ping-A.ps1'
			$selection.Names | Should -Contain 'Ping-B.Tests.ps1'
		}

		It "adds the Infrastructure tests only when a function file is added or removed" {
			(Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Alpha/Functions/Get-Leaf.ps1').Names | Should -Not -Contain 'Infrastructure-Docs.Tests.ps1'
			$added = Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Alpha/Functions/Get-Leaf.ps1' -AddedPaths 'Windows/PowerShell/Modules/Alpha/Functions/Get-Leaf.ps1'
			$added.Names | Should -Contain 'Infrastructure-Docs.Tests.ps1'
		}

		It "still finds the callers of a deleted function by its name" {
			$selection = Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Alpha/Functions/Get-Gone.ps1' -DeletedPaths 'Windows/PowerShell/Modules/Alpha/Functions/Get-Gone.ps1'
			$selection.Names | Should -Contain 'Infrastructure-Docs.Tests.ps1'
			$selection.Result.FullSuite | Should -BeFalse
		}

		It "adds what the runtime impact map says executed the function" {
			$map = @{ 'Modules/Alpha/Functions/Get-Leaf.ps1' = @('Modules/Tests/Modules/Beta/Unrelated.Tests.ps1') }
			$selection = Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Alpha/Functions/Get-Leaf.ps1' -ImpactMap $map
			$selection.Names | Should -Contain 'Unrelated.Tests.ps1'
		}
	}

	Context "Test files and fixtures" {
		It "selects a changed test file itself" {
			(Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Tests/Modules/Beta/Unrelated.Tests.ps1').Names | Should -Be @('Unrelated.Tests.ps1')
		}

		It "selects nothing for a deleted test file" {
			$selection = Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Tests/Modules/Beta/Gone.Tests.ps1' -DeletedPaths 'Windows/PowerShell/Modules/Tests/Modules/Beta/Gone.Tests.ps1'
			$selection.Names.Count | Should -Be 0
			$selection.Result.FullSuite | Should -BeFalse
		}

		It "fans a changed fixture out to every test that uses it" {
			(Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Tests/Modules/Support/FakeThing.ps1').Names | Should -Be @('Uses-Fake.Tests.ps1')
		}

		It "runs everything for a fixture no test references" {
			(Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Tests/Modules/Support/Orphan.ps1').Result.FullSuite | Should -BeTrue
		}
	}

	Context "Documentation and manifests" {
		It "selects only the Infrastructure tests for a docs-only change" {
			$selection = Get-Selected -ChangedPaths 'docs/modules/alpha.md', 'AGENTS.md', 'AI/Instructions/Style.md', 'AI/Context/Map.md'
			$selection.Names | Should -Be @('Infrastructure-Docs.Tests.ps1')
			$selection.Result.FullSuite | Should -BeFalse
		}

		It "selects the Infrastructure tests and the module's tests for a manifest change" {
			$selection = Get-Selected -ChangedPaths 'Windows/PowerShell/Modules/Alpha/Alpha.psd1'
			$selection.Names | Should -Contain 'Infrastructure-Docs.Tests.ps1'
			$selection.Names | Should -Contain 'Get-Leaf.Tests.ps1'
			$selection.Names | Should -Contain 'Invoke-Middle.Tests.ps1'
			$selection.Names | Should -Not -Contain 'Start-Top.Tests.ps1'
		}
	}

	Context "What analysis cannot see the consumers of" {
		It "runs the full suite for <Path>" -ForEach @(
			@{ Path = 'Windows/PowerShell/Configuration.psd1' }
			@{ Path = 'Windows/PowerShell/Configuration.local.psd1' }
			@{ Path = 'Windows/PowerShell/Microsoft.PowerShell_profile.ps1' }
			@{ Path = 'Windows/PowerShell/Modules/Tests/Invoke-TestSuite.ps1' }
			@{ Path = 'Windows/PowerShell/Modules/Tests/Get-TestImpact.ps1' }
			@{ Path = 'Windows/PowerShell/Modules/Tests/RequiredPesterVersion.txt' }
			@{ Path = 'Windows/PowerShell/Modules/Alpha/Alpha.psm1' }
			@{ Path = 'Windows/PowerShell/Modules/Logging/Functions/Write-Log.ps1' }
			@{ Path = 'Windows/PowerShell/Modules/Window/WindowNative.cs' }
			@{ Path = 'Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.csv' }
			@{ Path = 'Windows/PowerShell/Modules/Window/WindowModuleState.ps1' }
			@{ Path = 'AI/Skills/research/SKILL.md' }
			@{ Path = 'VSCode/settings.json' }
			@{ Path = 'some/unknown/file.txt' }
		) {
			$selection = Get-Selected -ChangedPaths $Path
			$selection.Result.FullSuite | Should -BeTrue
			@($selection.Result.FullSuiteReasons).Count | Should -BeGreaterThan 0
		}

		It "runs the full suite when any one of several changes needs it" {
			$selection = Get-Selected -ChangedPaths 'docs/modules/alpha.md', 'Windows/PowerShell/Configuration.psd1'
			$selection.Result.FullSuite | Should -BeTrue
		}
	}

	It "selects nothing when nothing changed" {
		$selection = Get-Selected -ChangedPaths @()
		$selection.Names.Count | Should -Be 0
		$selection.Result.FullSuite | Should -BeFalse
	}
}

Describe "Get-TestReferenceMap" {
	BeforeEach {
		$script:Cache = Join-Path $TestDrive ("refs_{0}.json" -f [guid]::NewGuid().ToString('N'))
		$script:File = Join-Path $TestDrive ("Caller_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
		Set-Content -LiteralPath $script:File -Value 'function Caller { Get-Leaf; & "Start-Top" }'
	}

	It "finds calls and string references to the given names" {
		$map = Get-TestReferenceMap -Path $script:File -Names 'Get-Leaf', 'Start-Top', 'Ping-A' -RootPath $TestDrive
		@($map[$script:File] | Sort-Object) | Should -Be @('Get-Leaf', 'Start-Top')
	}

	It "re-reads a file whose content changed even when it is cached" {
		Get-TestReferenceMap -Path $script:File -Names 'Get-Leaf', 'Ping-A' -RootPath $TestDrive -CachePath $script:Cache | Out-Null
		Set-Content -LiteralPath $script:File -Value 'function Caller { Ping-A }'
		$map = Get-TestReferenceMap -Path $script:File -Names 'Get-Leaf', 'Ping-A' -RootPath $TestDrive -CachePath $script:Cache
		@($map[$script:File]) | Should -Be @('Ping-A')
	}

	It "re-reads everything when the name set changes" {
		Get-TestReferenceMap -Path $script:File -Names 'Get-Leaf' -RootPath $TestDrive -CachePath $script:Cache | Out-Null
		$map = Get-TestReferenceMap -Path $script:File -Names 'Get-Leaf', 'Start-Top' -RootPath $TestDrive -CachePath $script:Cache
		@($map[$script:File]) | Should -Contain 'Start-Top'
	}

	It "rebuilds from a corrupt cache" {
		Set-Content -LiteralPath $script:Cache -Value '{ broken'
		$map = Get-TestReferenceMap -Path $script:File -Names 'Get-Leaf' -RootPath $TestDrive -CachePath $script:Cache
		@($map[$script:File]) | Should -Be @('Get-Leaf')
	}
}
