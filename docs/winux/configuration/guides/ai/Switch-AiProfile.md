# Switch-AiProfile

Switches this machine to another AI profile in one call: it records the pick in the administrator-owned switch file, redeploys the rules and the managed settings, and runs `Test-AiProfile`. The profiles it switches between are `AiProfiles.Profiles`, configured on the [`Resolve-AiProfile`](Resolve-AiProfile.md) page; the switch file sits next to the `managed-settings` destination of `AiHarnesses`, configured on the [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) page.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Switch-AiProfile
Switch-AiProfile Work
Switch-AiProfile Personal -Full
Switch-AiProfile Work -WhatIf
Switch-AiProfile -Reset
```

Without arguments it reports the current profile, then offers the configured profiles in a menu (plus `Reset` while a switch is in effect); Enter changes nothing. Run it in an elevated PowerShell, or let it rerun itself in one. Afterwards restart every open Claude Code session and, when `Test-AiProfile` names another Plan, log in to it (`claude`, `/logout`, `/login`).

## Related

- [`Switch-AiProfile` in the AI module reference](../../../modules/ai.md#switch-aiprofile)
- [AI Profiles - Switching A Machine](../../../ai/profiles.md#switching-a-machine)
- [AI configuration guides](README.md)
