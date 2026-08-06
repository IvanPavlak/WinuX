#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-SymbolicLinkEntries.ps1"
}

Describe "Get-SymbolicLinkEntries" {
	BeforeEach {
		$script:links = @{
			Git       = @{
				Path   = "C:\Users\Test\.gitconfig"
				Target = "C:\Repo\Git\.gitconfig"
			}
			WSLSSH    = @{
				Path   = "/home/test/.ssh/config"
				Target = "/mnt/c/Users/Test/.ssh/config"
			}
			PowerToys = @{
				Settings      = @{
					Path   = "C:\Users\Test\PowerToys\settings.json"
					Target = "C:\Repo\FancyZones\settings.json"
				}
				CustomLayouts = @{
					Path   = "C:\Users\Test\PowerToys\custom-layouts.json"
					Target = "C:\Repo\FancyZones\custom-layouts.json"
				}
			}
		}
	}

	It "flattens nested groups into dotted full keys" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links

		$entries.Count | Should -Be 4
		$entries.FullKey | Should -Contain "Git"
		$entries.FullKey | Should -Contain "PowerToys.Settings"
		$entries.FullKey | Should -Contain "PowerToys.CustomLayouts"
	}

	It "flags forward-slash entries as WSL" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links

		($entries | Where-Object FullKey -eq "WSLSSH").IsWSL | Should -BeTrue
		($entries | Where-Object FullKey -eq "Git").IsWSL | Should -BeFalse
	}

	It "-Scope WSL returns only WSL entries" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links -Scope WSL

		$entries.Count | Should -Be 1
		$entries[0].FullKey | Should -Be "WSLSSH"
	}

	It "-Scope Windows returns only Windows entries" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links -Scope Windows

		$entries.Count | Should -Be 3
		$entries.IsWSL | Should -Not -Contain $true
	}

	It "-Name matches a top-level entry" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links -Name Git

		$entries.Count | Should -Be 1
		$entries[0].FullKey | Should -Be "Git"
	}

	It "-Name on a group selects everything beneath it" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links -Name PowerToys

		$entries.Count | Should -Be 2
		$entries.FullKey | Should -Contain "PowerToys.Settings"
		$entries.FullKey | Should -Contain "PowerToys.CustomLayouts"
	}

	It "-Name reaches nested entries via the dotted path or the bare key" {
		(Get-SymbolicLinkEntries -SymbolicLinks $script:links -Name "PowerToys.Settings").FullKey | Should -Be "PowerToys.Settings"
		(Get-SymbolicLinkEntries -SymbolicLinks $script:links -Name "Settings").FullKey | Should -Be "PowerToys.Settings"
	}

	It "-Name supports wildcards and multiple patterns" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links -Name "WSL*", "Git"

		$entries.Count | Should -Be 2
		$entries.FullKey | Should -Contain "WSLSSH"
		$entries.FullKey | Should -Contain "Git"
	}

	It "-Name and -Scope combine to an empty selection" {
		$entries = Get-SymbolicLinkEntries -SymbolicLinks $script:links -Scope Windows -Name "WSL*"

		$entries.Count | Should -Be 0
	}

	It "returns an empty list for an empty hashtable" {
		(Get-SymbolicLinkEntries -SymbolicLinks @{}).Count | Should -Be 0
	}
}
