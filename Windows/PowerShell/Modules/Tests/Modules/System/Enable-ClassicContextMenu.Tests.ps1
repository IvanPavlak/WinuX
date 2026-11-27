#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Enable-ClassicContextMenu.ps1"

	$script:ShortenedMenuClassId = '{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
	$script:RedesignedMenuClassId = '{51668040-5e31-4023-bbe3-149163bd80f1}'

	# Stands in for a registry key: GetValue('') is the key's default value.
	function New-OverrideKeyStub {
		param($DefaultValue)

		$key = [PSCustomObject]@{ DefaultValue = $DefaultValue }
		$key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($name) $this.DefaultValue } -PassThru
	}
}

Describe "Enable-ClassicContextMenu" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Restart-Explorer { }
		Mock New-Item { }
		Mock Test-Path { $true }
		Mock Get-Item { $null }
	}

	It "overrides both menu classes for the current user and restarts Explorer once" {
		Enable-ClassicContextMenu

		Should -Invoke New-Item -Times 2 -Exactly
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
			$Path -eq "HKCU:\Software\Classes\CLSID\$script:ShortenedMenuClassId\InprocServer32" -and $Value -eq '' -and $Force
		}
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
			$Path -eq "HKCU:\Software\Classes\CLSID\$script:RedesignedMenuClassId\InprocServer32" -and $Value -eq '' -and $Force
		}
		Should -Invoke Restart-Explorer -Times 1 -Exactly
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq 'Classic context menu enabled' }
	}

	It "writes only the override that is missing" {
		Mock Get-Item { New-OverrideKeyStub -DefaultValue '' } -ParameterFilter { $LiteralPath -like "*$script:ShortenedMenuClassId*" }

		Enable-ClassicContextMenu

		Should -Invoke New-Item -Times 1 -Exactly
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $Path -like "*$script:RedesignedMenuClassId*" }
		Should -Invoke Restart-Explorer -Times 1 -Exactly
	}

	It "treats an override key without a default value as missing" {
		Mock Get-Item { New-OverrideKeyStub -DefaultValue $null }

		Enable-ClassicContextMenu

		Should -Invoke New-Item -Times 2 -Exactly
	}

	It "changes nothing and leaves Explorer running when both overrides are in place" {
		Mock Get-Item { New-OverrideKeyStub -DefaultValue '' }

		Enable-ClassicContextMenu

		Should -Invoke New-Item -Times 0
		Should -Invoke Restart-Explorer -Times 0
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -eq 'Classic context menu already enabled' }
	}

	It "leaves a class the machine does not register alone" {
		Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like "*$script:RedesignedMenuClassId*" }

		Enable-ClassicContextMenu

		Should -Invoke New-Item -Times 1 -Exactly
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $Path -like "*$script:ShortenedMenuClassId*" }
	}

	It "changes nothing when the machine registers neither class" {
		Mock Test-Path { $false }

		Enable-ClassicContextMenu

		Should -Invoke New-Item -Times 0
		Should -Invoke Restart-Explorer -Times 0
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like 'This Windows version has no Windows 11 context menu*' }
	}

	It "reports a failed override and does not restart Explorer when nothing was written" {
		Mock New-Item { throw "access denied" }

		Enable-ClassicContextMenu

		Should -Invoke Write-LogError -Times 2 -Exactly
		Should -Invoke Restart-Explorer -Times 0
	}
}
