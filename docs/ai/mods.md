# AI Mods

Machine-global Claude Code mods: function-hook plugins kept in the repository, vendored from their own upstream repositories at a pinned commit, and deployed so every Claude Code session on the machine - terminal or desktop Code tab, on Windows and inside WSL - loads them without adding anything to any project. The mods counterpart of [AI Skills](skills.md).

Mods are one kind of AI artifact: where they live, how they are vendored and how they are deployed is the mechanism described on [AI Artifacts](artifacts.md). This page covers what is particular to mods, and the Claude Code plugin marketplaces, which install plugins without vendoring them.

Mods are **opt-in**: the base names no mod sources, `AI/Mods` holds only its README, and a vanilla bootstrap deploys into no app until `AiArtifacts.Deploy` names `claude-code` and `BootstrapConfig.Steps.AiArtifacts` is on.

## What a mod is

A mod is a Claude Code plugin made of function hooks: a folder `AI\Mods\<source>\<mod>\` holding `.claude-plugin/plugin.json` (name, version, description, optional `userConfig` and type contract) and a hooks module (`hooks/hooks.json` naming `hooks/register.tsx`). Its hooks draw bands above the prompt, panes, status entries and toasts, and hook engine events such as tool calls, prompts and session measurements. Mods are authored with Claude Code's `plugin-authoring` skill, checked with `claude plugin validate <folder>` and tested with `claude plugin test <folder>`.

## Design

Claude Code loads plugins from the folders named in `CLAUDE_CODE_PLUGIN_DIRS` - one path per plugin, in the platform's path-list separator (`;` on Windows, `:` inside WSL). It reads that variable from the process environment or from the `env` block of the **user** settings file `~/.claude/settings.json`, never from a project's settings. Deployment therefore has two halves, both done by [Deploy-AiArtifacts](../modules/ai.md#deploy-aiartifacts) for the mods destination of the `claude-code` harness:

1. **Links.** Each mod is linked individually into `~\.claude\mods`, one symbolic link per mod (`Placement = "Each"`), with the rules every kind shares: a folder link into the repository is replaced by a real folder, dangling links into the artifacts root are pruned, links to anything else are never touched.
2. **One settings key.** The destination's `claude-plugin-dirs` hook then rewrites only `env.CLAUDE_CODE_PLUGIN_DIRS` of the user settings file, keeping every other setting.

| Platform | Mods folder | Settings file | Separator |
| -------- | ----------- | ------------- | --------- |
| Windows | `~\.claude\mods\<mod>` | `~\.claude\settings.json` | `;` |
| WSL | `/home/<DefaultWSLUsername>/.claude/mods/<mod>` | `/home/<user>/.claude/settings.json`, edited through `\\wsl.localhost\<distro>` | `:` |

### The settings merge

[Resolve-AiModsPluginDirs](../modules/ai.md#resolve-aimodsplugindirs) computes the new value and [Set-ClaudeSettingsEnv](../modules/ai.md#set-claudesettingsenv) writes it:

- The deployed links come first, one per mod.
- Every entry you added by hand that is not under the mods folder follows, verbatim and in its original order.
- Entries under the mods folder without a mod any more are dropped.
- The rest of `settings.json` - every other key, nested object and `env` variable - is read and written back unchanged. An unparseable file is left untouched and reported.

### The CLI check

The changelog of Claude Code does not name the first build with the hooks-module API, so the practical gate is the CLI's own validator. After deploying, the hook runs [Test-AiModsCli](../modules/ai.md#test-aimodscli) (`claude plugin validate` on every mod). A missing CLI, or one that rejects a mod, only produces a warning - links and settings are always deployed, so installing or updating the CLI later is enough:

- `Claude Code CLI (claude) not found on PATH - mods are deployed but cannot be used until the Claude Code CLI is installed or updated!`
- `claude plugin validate failed for [<names>] - mods are deployed but cannot be used until the Claude Code CLI is updated or the mod is fixed!`

### Vendoring

A `Sources` entry with `Mods` folders vendors mods from GitHub through [Update-AiArtifacts](../modules/ai.md#update-aiartifacts) ([Vendoring](artifacts.md#vendoring)). What is particular to mods:

- A configured folder (`.` for the repository root) that itself holds `.claude-plugin/plugin.json` is one mod - the usual shape of a mod developed in its own repository. Otherwise each of its subfolders that holds the manifest is a mod.
- Each mod is named by its `plugin.json` `name`.
- Top-level entries listed in `SkipPaths` (default `.git`, `.github`, `tests`, `design`, `docs`) stay upstream: only what Claude Code loads is vendored.
- A source may be a private repository: with a GitHub token (`GITHUB_TOKEN`, `GH_TOKEN`, or a signed-in GitHub CLI) both requests authenticate, so a mod you keep private until it is ready vendors like a public one. Pin `Ref` to a release tag for a known-good version and bump it to upgrade.

### Marketplaces

A plugin published through a Claude Code plugin marketplace (a repository carrying `.claude-plugin/marketplace.json`) does not need vendoring at all: Claude Code installs it with `claude plugin install <plugin>@<marketplace>` and keeps it updated. [Deploy-AiMarketplaces](../modules/ai.md#deploy-aimarketplaces) makes that part of Bootstrap, from the `AiMarketplaces` section:

1. **Register.** Every marketplace under `AiMarketplaces.Marketplaces` is written to `extraKnownMarketplaces.<name>` of the user settings file through [Set-ClaudeSettingsKey](../modules/ai.md#set-claudesettingskey), the generic sibling of `Set-ClaudeSettingsEnv`, so Claude Code knows it on every start. Inside WSL the same keys go to the WSL user's settings file through the `\\wsl.localhost` share.
2. **Write the variables.** Every entry of a marketplace's `Env` is written to the `env` block of the same file through [Set-ClaudeSettingsEnv](../modules/ai.md#set-claudesettingsenv), every other variable kept. Claude Code reads its own environment from that block in every session, the desktop app's included, which makes it the one place for a switch a plugin needs but cannot set for itself, because none of its code runs until the switch is on. The case that prompted it: Claude Code 2.1.286 (the CLI and the copy the desktop app bundles) loads hooks modules only with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` set to `1`; 2.1.287 and later ignore it. Values are strings, names must be valid variable names, and marketplaces are written in name order, so a variable two of them name ends with the value of the last.
3. **Seed options.** Every entry of `AiMarketplaces.PluginConfigs` is written beneath the plugin's `pluginConfigs` entry, one child key at a time, so an option set through `/plugin` that the repository does not name survives. A plugin a configured marketplace lists is keyed the way Claude Code keys an installed plugin, `pluginConfigs.<plugin>@<marketplace>`; any other name is written as given, the shape of a folder-loaded plugin. Values are typed as the plugin's `userConfig` declares them: a boolean option takes `$true`, not the string `"true"`, which a plugin drops as invalid.
4. **Add and install.** With the `claude` CLI on PATH, every configured marketplace that `claude plugin marketplace list --json` does not show is added with `claude plugin marketplace add <owner/name>` (the settings key alone takes effect only on the engine's next start), and every plugin an entry lists is installed as `<plugin>@<name>` unless `claude plugin list --json` already shows it; a missing CLI only warns. With WSL configured, the same runs again against the CLI installed inside WSL (`wsl -d <distro> -u <user>`, a login shell); a `claude` that WSL resolves under `/mnt/` is the Windows CLI reached through interop and counts as missing there, since it would install into the Windows profile. Updates stay with `claude plugin update`, or the marketplace's auto-update in `/plugin`.

Vendoring and marketplaces are two ways to load one plugin: give each plugin one of them. A folder-loaded mod and a marketplace install of the same plugin would draw twice. A folder in `env.CLAUDE_CODE_PLUGIN_DIRS` that holds a plugin a configured marketplace installs is reported as a warning and left in place: Claude Code would load two copies, and the folder copy reads its options from `pluginConfigs.<plugin>`, not `<plugin>@<marketplace>`, so it draws with its defaults. Load a development clone with `claude --plugin-dir <clone>` for one session instead of listing it in the settings. Vendoring keeps a pinned copy that works offline and carries hand-written mods; a marketplace keeps you on the published release with no refresh step.

## Configuration

```powershell
# Configuration.local.psd1
@{
    AiArtifacts    = @{
        # Upstreams vendored by Update-AiArtifacts into AI\Mods\<name>\<mod>\.
        Sources = @{
            "my-mod" = @{
                Repository = "MyOrg/MyMod"                                   # owner/name
                Ref        = "v1.0.0"                                        # branch, tag or commit
                Mods       = @(".")                                          # "." = the repository root is the mod
                Exclude    = @()                                             # mod names to leave out
                SkipPaths  = @(".git", ".github", "tests", "design", "docs") # top-level entries not vendored
            }
        }
        Deploy  = @{ Default = @("claude-code") }
    }
    # Plugins installed from a marketplace instead (Deploy-AiMarketplaces).
    AiMarketplaces = @{
        Marketplaces  = @{
            "my-marketplace" = @{
                Repository = "MyOrg/MyMarketplace"   # owner/name; the marketplace is named by the key
                Plugins    = @("my-plugin")          # installed as <plugin>@<key>
                Env        = @{ CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = "1" }   # written to env.<name>; strings
            }
        }
        PluginConfigs = @{
            "my-plugin" = @{ options = @{ theme = "dark"; pulse = $true } }   # beneath pluginConfigs.my-plugin@my-marketplace
        }
    }
    BootstrapConfig = @{
        Steps = @{
            AiArtifacts    = $true
            AiMarketplaces = $true
        }
    }
}
```

The 1.5 `AiMods` section (`Root`, `Harnesses`, `Sources` with `Folders`) keeps working until 2.0.0: its `Sources` are read as `AiArtifacts` sources. See [Migrating from 1.5](artifacts.md#migrating-from-15).

## Verification (per machine, after enabling)

1. Run `Update-AiArtifacts` once (or pull a repository that already carries the vendored folders), review the diff, then run `Deploy-AiArtifacts -Kind Mods` (or full `Bootstrap`) as admin.
2. `Get-ChildItem ~\.claude\mods | Select-Object Name, LinkTarget` shows one link per mod into `AI\Mods\<source>\<mod>`.
3. `(Get-Content ~\.claude\settings.json -Raw | ConvertFrom-Json).env.CLAUDE_CODE_PLUGIN_DIRS` lists those links, and every other setting is still there.
4. `claude plugin validate ~\.claude\mods\<mod>` passes.
5. Start a new Claude Code session (terminal and desktop Code tab) and confirm the mod's band, pane or status entry appears. Inside WSL, check `/home/<user>/.claude/mods/<mod>` resolves through `/mnt/<drive>` and the WSL settings file carries the `:`-joined list.

## Related

- [AI Artifacts](artifacts.md) - the mechanism, the harness catalogue and migrating from 1.5
- [AI module reference](../modules/ai.md) - `Deploy-AiArtifacts`, `Update-AiArtifacts`, `Deploy-AiMarketplaces`, `Resolve-AiModsPluginDirs`, `Set-ClaudeSettingsEnv`, `Set-ClaudeSettingsKey`, `Test-AiModsCli`
- [Deploy-AiArtifacts configuration guide](../configuration/guides/ai/Deploy-AiArtifacts.md) - the `AiArtifacts` keys, decision by decision
- [Deploy-AiMarketplaces configuration guide](../configuration/guides/ai/Deploy-AiMarketplaces.md) - the `AiMarketplaces` keys
- [Update-AiArtifacts configuration guide](../configuration/guides/ai/Update-AiArtifacts.md) - the `AiArtifacts.Sources` keys
- [AI Skills](skills.md) - another artifact kind deployed into the same apps
- [Troubleshooting - AI Mods Issues](../reference/troubleshooting.md#ai-mods-issues)
