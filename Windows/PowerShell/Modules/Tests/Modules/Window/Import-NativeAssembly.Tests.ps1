#Requires -Modules Pester

BeforeAll {
	$script:ImportScript = Join-Path (Get-RepositoryPath).Modules "Window\Import-NativeAssembly.ps1"

	# Every case compiles its own uniquely named type, and runs the import in a fresh pwsh: a type,
	# once loaded, stays loaded for the life of a process, so "loaded from the cache" can only be
	# observed by a process that has not compiled it itself.
	function New-NativeSource {
		param([string]$Directory, [int]$Value = 1)
		$namespace = "NativeCacheTest" + [guid]::NewGuid().ToString('N')
		$path = Join-Path $Directory "Native.cs"
		Set-Content -LiteralPath $path -Value "namespace $namespace { public static class Probe { public static int Value() { return $Value; } } }"
		[pscustomobject]@{ Path = $path; TypeName = "$namespace.Probe" }
	}

	function Invoke-ImportInChild {
		param([string]$SourcePath, [string]$TypeName, [string]$CacheDirectory)
		pwsh -NoProfile -NonInteractive -Command {
			param($Script, $Source, $Type, $Cache)
			$result = & $Script -SourcePath $Source -TypeName $Type -CacheDirectory $Cache
			[pscustomobject]@{
				Source       = $result.Source
				AssemblyPath = $result.AssemblyPath
				Value        = $(if (([System.Management.Automation.PSTypeName]$Type).Type) { ([type]$Type)::Value() })
			}
		} -args $script:ImportScript, $SourcePath, $TypeName, $CacheDirectory
	}
}

Describe "Import-NativeAssembly" -Tag 'Integration' {
	BeforeEach {
		$script:Work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
		$script:Cache = Join-Path $script:Work 'cache'
		New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
	}

	It "compiles into the cache the first time, and every later process loads that assembly" {
		$source = New-NativeSource -Directory $script:Work

		$first = Invoke-ImportInChild -SourcePath $source.Path -TypeName $source.TypeName -CacheDirectory $script:Cache
		$first.Source | Should -Be 'Compiled'
		$first.Value | Should -Be 1
		$first.AssemblyPath | Should -Exist

		$second = Invoke-ImportInChild -SourcePath $source.Path -TypeName $source.TypeName -CacheDirectory $script:Cache
		$second.Source | Should -Be 'Cache'
		$second.AssemblyPath | Should -Be $first.AssemblyPath
		$second.Value | Should -Be 1
	}

	It "rebuilds when the source changes, and removes the superseded assembly" {
		$source = New-NativeSource -Directory $script:Work -Value 1
		$old = Invoke-ImportInChild -SourcePath $source.Path -TypeName $source.TypeName -CacheDirectory $script:Cache

		Set-Content -LiteralPath $source.Path -Value ((Get-Content -LiteralPath $source.Path -Raw) -replace 'return 1;', 'return 2;')
		$new = Invoke-ImportInChild -SourcePath $source.Path -TypeName $source.TypeName -CacheDirectory $script:Cache

		$new.Source | Should -Be 'Compiled'
		$new.Value | Should -Be 2
		$new.AssemblyPath | Should -Not -Be $old.AssemblyPath
		$old.AssemblyPath | Should -Not -Exist
	}

	It "falls back to compiling in memory when the cached assembly cannot be loaded" {
		$source = New-NativeSource -Directory $script:Work
		$first = Invoke-ImportInChild -SourcePath $source.Path -TypeName $source.TypeName -CacheDirectory $script:Cache
		[System.IO.File]::WriteAllBytes($first.AssemblyPath, [byte[]](1..64))

		$broken = Invoke-ImportInChild -SourcePath $source.Path -TypeName $source.TypeName -CacheDirectory $script:Cache
		$broken.Source | Should -Be 'InMemory'
		$broken.Value | Should -Be 1
	}

	It "falls back to compiling in memory when the cache folder cannot be created" {
		$source = New-NativeSource -Directory $script:Work
		# A file where the cache folder should be.
		$blocked = Join-Path $script:Work 'blocked'
		Set-Content -LiteralPath $blocked -Value 'not a folder'

		$result = Invoke-ImportInChild -SourcePath $source.Path -TypeName $source.TypeName -CacheDirectory (Join-Path $blocked 'cache')
		$result.Source | Should -Be 'InMemory'
		$result.Value | Should -Be 1
	}

	It "does nothing when the type is already loaded, and reports a missing source" {
		& $script:ImportScript -SourcePath (Join-Path $script:Work 'none.cs') -TypeName 'System.String' -CacheDirectory $script:Cache |
			ForEach-Object { $_.Source } | Should -Be 'Loaded'
		& $script:ImportScript -SourcePath (Join-Path $script:Work 'none.cs') -TypeName 'No.Such.Type' -CacheDirectory $script:Cache |
			ForEach-Object { $_.Source } | Should -Be 'Missing'
	}
}
