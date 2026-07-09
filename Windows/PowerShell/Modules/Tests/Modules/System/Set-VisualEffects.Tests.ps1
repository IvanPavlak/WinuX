#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-VisualEffects.ps1"
}

Describe "Set-VisualEffects" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			VisualEffects = $null
		}
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Restart-Explorer { }
	}

	It "returns without side effects when VisualEffects is missing from configuration" {
		{ Set-VisualEffects } | Should -Not -Throw

		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Restart-Explorer -Times 0
	}

	It "returns without side effects when VisualEffects is empty" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{} }

		{ Set-VisualEffects } | Should -Not -Throw

		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Restart-Explorer -Times 0
	}

	It "warns and applies nothing when only unknown keys are configured" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{ NotARealEffect = $true } }

		{ Set-VisualEffects } | Should -Not -Throw

		# One warning for the unknown key, one for having nothing applicable left
		Should -Invoke Write-LogWarning -Times 2
		Should -Invoke Restart-Explorer -Times 0
	}

	It "skips applying when every configured effect already matches" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{ EnablePeek = $false } }
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 3 } else { 0 }
		}
		Mock Set-ItemProperty { }

		{ Set-VisualEffects } | Should -Not -Throw

		Should -Invoke Set-ItemProperty -Times 0
		Should -Invoke Restart-Explorer -Times 0
		Should -Invoke Write-LogWarning -Times 1
	}

	It "applies a mismatched registry effect and restarts Explorer once" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{ EnablePeek = $false } }
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 3 } else { 1 }
		}
		Mock Test-Path { $true }
		Mock Set-ItemProperty { }

		{ Set-VisualEffects } | Should -Not -Throw

		Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "EnableAeroPeek" -and $Value -eq 0 }
		Should -Invoke Restart-Explorer -Times 1
		Should -Invoke Write-LogSuccess -Times 1
		# Disabled effects render as red rows
		Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Error" -and $Message -like "*EnablePeek*disabled*" }
	}

	It "reports already-matching effects as yellow skipped rows while applying the rest" {
		$script:Configuration = [PSCustomObject]@{
			VisualEffects = @{
				EnablePeek                        = $false
				ShowTranslucentSelectionRectangle = $true
			}
		}
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 3 }
			elseif ($Name -eq "EnableAeroPeek") { 0 }
			else { 0 }
		}
		Mock Test-Path { $true }
		Mock Set-ItemProperty { }

		{ Set-VisualEffects } | Should -Not -Throw

		# EnablePeek already off => yellow skipped row, no write
		Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Warning" -and $Message -like "*EnablePeek*skipped*" }
		# ShowTranslucentSelectionRectangle turned on => green row + registry write
		Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Style -eq "Success" -and $Message -like "*ShowTranslucentSelectionRectangle*enabled*" }
		Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "ListviewAlphaSelect" -and $Value -eq 1 }
	}

	It "writes the inverted registry value for ShowThumbnailsInsteadOfIcons" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{ ShowThumbnailsInsteadOfIcons = $true } }
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 3 } else { 1 }
		}
		Mock Test-Path { $true }
		Mock Set-ItemProperty { }

		{ Set-VisualEffects } | Should -Not -Throw

		# Effect ON maps to IconsOnly = 0 (thumbnails instead of icons)
		Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "IconsOnly" -and $Value -eq 0 }
	}

	It "sets the Custom profile radio button when VisualFXSetting differs" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{ EnablePeek = $false } }
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 1 } else { 0 }
		}
		Mock Test-Path { $true }
		Mock Set-ItemProperty { }

		{ Set-VisualEffects } | Should -Not -Throw

		# The effect itself already matches - only the radio button is written
		Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "VisualFXSetting" -and $Value -eq 3 }
		Should -Invoke Restart-Explorer -Times 0
	}

	It "treats a missing registry value as a mismatch and applies it" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{ AnimationsInTheTaskbar = $false } }
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 3 } else { throw "Property TaskbarAnimations does not exist" }
		}
		Mock Test-Path { $true }
		Mock Set-ItemProperty { }

		{ Set-VisualEffects } | Should -Not -Throw

		Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "TaskbarAnimations" -and $Value -eq 0 }
		Should -Invoke Restart-Explorer -Times 1
	}

	It "creates the registry key path when it does not exist" {
		$script:Configuration = [PSCustomObject]@{ VisualEffects = @{ SaveTaskbarThumbnailPreviews = $true } }
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 3 } else { throw "Key does not exist" }
		}
		Mock Test-Path { $false }
		Mock New-Item { }
		Mock Set-ItemProperty { }

		{ Set-VisualEffects } | Should -Not -Throw

		Should -Invoke New-Item -Times 1
		Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "AlwaysHibernateThumbnails" -and $Value -eq 1 }
	}

	It "continues applying remaining effects when one write fails" {
		$script:Configuration = [PSCustomObject]@{
			VisualEffects = @{
				EnablePeek                        = $false
				ShowTranslucentSelectionRectangle = $true
			}
		}
		Mock Get-ItemPropertyValue {
			if ($Name -eq "VisualFXSetting") { 3 } else { throw "Property does not exist" }
		}
		Mock Test-Path { $true }
		Mock Set-ItemProperty {
			if ($Name -eq "EnableAeroPeek") { throw "Access denied" }
		}

		{ Set-VisualEffects } | Should -Not -Throw

		Should -Invoke Write-LogError -Times 1
		Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Name -eq "ListviewAlphaSelect" -and $Value -eq 1 }
		Should -Invoke Write-LogSuccess -Times 1
	}
}
