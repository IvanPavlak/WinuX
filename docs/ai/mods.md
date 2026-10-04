# AI Mods

Machine-global Claude Code mods: function-hook plugins kept in the repository, vendored from their own upstream repositories at a pinned commit, and deployed so every Claude Code session on the machine - terminal or desktop Code tab, on Windows and inside WSL - loads them without adding anything to any project. The mods counterpart of [AI Skills](skills.md).

AI Mods is **opt-in**: the mechanism ships with WinuX, but the base configuration names no mod sources, the `AI/Mods` root holds only its README, and `BootstrapConfig.Steps.AiMods` is OFF, so a vanilla bootstrap deploys nothing.

## What a mod is

A mod is a Claude Code plugin made of function hooks: a folder holding `.claude-plugin/plugin.json` (name, version, description, optional `userConfig` and type contract) and a hooks module (`hooks/hooks.json` naming `hooks/register.tsx`). Its hooks draw bands above the prompt, panes, status entries and toasts, and hook engine events such as tool calls, prompts and session measurements. Mods are authored with Claude Code's `plugin-authoring` skill, checked with `claude plugin validate <folder>` and tested with `claude plugin test <folder>`.

## Design

Claude Code loads plugins from the folders named in `CLAUDE_CODE_PLUGIN_DIRS` - one path per plugin, in the platform's path-list separator (`;` on Windows, `:` inside WSL). It reads that variable from the process environment or from the `env` block of the **user** settings file `~/.claude/settings.json`, never from a project's settings. Deployment therefore has two halves:

1. **Links.** [Deploy-AiMods](../modules/ai.md#deploy-aimods) links each mod individually into the harness directory, one symbolic link per mod, with the same rules as [Deploy-AiSkills](../modules/ai.md#deploy-aiskills): a whole-directory link into the repository at the harness path is replaced by a real directory, dangling links into the mods root are pruned, links to anything else are never touched.
2. **One settings key.** It then rewrites only `env.CLAUDE_CODE_PLUGIN_DIRS` of the user settings file, keeping every other setting.

| Platform | Harness directory | Settings file | Separator | Deployed by |
| -------- | ----------------- | ------------- | --------- | ----------- |
| Windows | `~\.claude\mods\<mod>` | `~\.claude\settings.json` | `;` | `Deploy-AiMods` |
| WSL | `/home/<DefaultWSLUsername>/.claude/mods/<mod>` | `/home/<user>/.claude/settings.json`, edited through `\\wsl.localhost\<distro>` | `:` | `Deploy-AiMods` |

The repository keeps mods under `AI/Mods/<source>/<mod>/` - one subfolder per source, so a vendored upstream and your own mods (`own`) never mix. The same mod name under two sources is reported and the first source by name wins.

### The settings merge

[Resolve-AiModsPluginDirs](../modules/ai.md#resolve-aimodsplugindirs) computes the new value and [Set-ClaudeSettingsEnv](../modules/ai.md#set-claudesettingsenv) writes it:

- The deployed links come first, one per mod, from the FIRST harness directory only, so no mod is ever loaded twice.
- Every entry you added by hand that is not under the harness directory follows, verbatim and in its original order.
- Entries under the harness directory without a mod any more are dropped.
- The rest of `settings.json` - every other key, nested object and `env` variable - is read and written back unchanged. An unparseable file is left untouched and reported.

### The CLI check

The changelog of Claude Code does not name the first build with the hooks-module API, so the practical gate is the CLI's own validator. After deploying, [Test-AiModsCli](../modules/ai.md#test-aimodscli) runs `claude plugin validate` on every mod. A missing CLI, or one that rejects a mod, only produces a warning - links and settings are always deployed, so installing or updating the CLI later is enough:

- `Claude Code CLI (claude) not found on PATH - mods are deployed but cannot be used until the Claude Code CLI is installed or updated!`
- `claude plugin validate failed for [<names>] - mods are deployed but cannot be used until the Claude Code CLI is updated or the mod is fixed!`

### Vendoring

[Update-AiMods](../modules/ai.md#update-aimods) fills the vendored source folders from GitHub, the same way [Update-AiSkills](../modules/ai.md#update-aiskills) does for skills: it resolves the configured ref to an exact commit, downloads that commit's archive, and records provenance in `AI/Mods/<source>/UPSTREAM.md` (pinned commit, folders, exclusions, skipped paths, a table of every mod with its description) next to a copy of the upstream license. A source may be a private repository: with a GitHub token (`GITHUB_TOKEN`, `GH_TOKEN`, or a signed-in GitHub CLI) both requests authenticate, so a mod you keep private until it is ready vendors like a public one.

- A configured folder (default `.`, the repository root) that itself holds `.claude-plugin/plugin.json` is one mod - the usual shape of a mod developed in its own repository. Otherwise each of its subfolders that holds the manifest is a mod.
- Each mod is named by its `plugin.json` `name`.
- Top-level entries listed in `SkipPaths` (default `.git`, `.github`, `tests`, `design`, `docs`) stay upstream: only what Claude Code loads is vendored.
- Only the mods the previous manifest lists are replaced, so a folder you add by hand inside a source survives a refresh.
- `-Check` reports whether a source is behind upstream without writing anything.

It is a manual command, not a Bootstrap step: the vendored tree is committed, so a fresh machine only needs `Deploy-AiMods`. Pin `Ref` to a release tag for a known-good version and bump it to upgrade.

### Marketplaces

A plugin published through a Claude Code plugin marketplace (a repository carrying `.claude-plugin/marketplace.json`) does not need vendoring at all: Claude Code installs it with `claude plugin install <plugin>@<marketplace>` and keeps it updated. [Deploy-AiMarketplaces](../modules/ai.md#deploy-aimarketplaces) makes that part of Bootstrap, from the `AiMarketplaces` section:

1. **Register.** Every marketplace under `AiMarketplaces.Marketplaces` is written to `extraKnownMarketplaces.<name>` of the user settings file through [Set-ClaudeSettingsKey](../modules/ai.md#set-claudesettingskey), the generic sibling of `Set-ClaudeSettingsEnv`, so Claude Code knows it on every start. Inside WSL the same keys go to the WSL user's settings file through the `\\wsl.localhost` share.
2. **Seed options.** Every entry of `AiMarketplaces.PluginConfigs` is written beneath the plugin's `pluginConfigs` entry, one child key at a time, so an option set through `/plugin` that the repository does not name survives. A plugin a configured marketplace lists is keyed the way Claude Code keys an installed plugin, `pluginConfigs.<plugin>@<marketplace>`; any other name is written as given, the shape of a folder-loaded plugin.
3. **Add and install.** With the `claude` CLI on PATH, every configured marketplace that `claude plugin marketplace list --json` does not show is added with `claude plugin marketplace add <owner/name>` (the settings key alone takes effect only on the engine's next start), and every plugin an entry lists is installed as `<plugin>@<name>` unless `claude plugin list --json` already shows it; a missing CLI only warns. Updates stay with `claude plugin update`, or the marketplace's auto-update in `/plugin`.

Vendoring and marketplaces are two ways to load one plugin: give each plugin one of them. A folder-loaded mod and a marketplace install of the same plugin would draw twice. Vendoring keeps a pinned copy that works offline and carries hand-written mods; a marketplace keeps you on the published release with no refresh step.

## Configuration

```powershell
# Configuration.local.psd1
@{
    AiMods = @{
        # Where the mods live; one subfolder per source.
        Root      = "{RepoRoot}\AI\Mods"
        # Directories mods are linked into; the first is the one CLAUDE_CODE_PLUGIN_DIRS lists.
        # The WSL twin is derived from the {User} entry and DefaultWSLUsername.
        Harnesses = @("{User}\.claude\mods")
        # Upstreams vendored by Update-AiMods into Root\<name>\<mod>\.
        Sources   = @{
            "my-mod" = @{
                Repository = "MyOrg/MyMod"                                   # owner/name
                Ref        = "v1.0.0"                                        # branch, tag or commit
                Folders    = @(".")                                          # "." = the repository root is the mod
                Exclude    = @()                                             # mod names to leave out
                SkipPaths  = @(".git", ".github", "tests", "design", "docs") # top-level entries not vendored
            }
        }
    }
    # Plugins installed from a marketplace instead (Deploy-AiMarketplaces).
    AiMarketplaces = @{
        Marketplaces  = @{
            "my-marketplace" = @{
                Repository = "MyOrg/MyMarketplace"   # owner/name; the marketplace is named by the key
                Plugins    = @("my-plugin")          # installed as <plugin>@<key>
            }
        }
        PluginConfigs = @{
            "my-plugin" = @{ options = @{ theme = "dark" } }   # beneath pluginConfigs.my-plugin@my-marketplace
        }
    }
    BootstrapConfig = @{
        Steps = @{
            AiMods         = $true
            AiMarketplaces = $true
        }
    }
}
```

`Root` and `Harnesses` only need stating when you change them; the values above are the defaults. Arrays replace wholesale on merge.

## Verification (per machine, after enabling)

1. Run `Update-AiMods` once (or pull a repository that already carries the vendored folders), review the diff, then run `Deploy-AiMods` (or full `Bootstrap`) as admin.
2. `Get-ChildItem ~\.claude\mods | Select-Object Name, LinkTarget` shows one link per mod into `AI\Mods\<source>\<mod>`.
3. `(Get-Content ~\.claude\settings.json -Raw | ConvertFrom-Json).env.CLAUDE_CODE_PLUGIN_DIRS` lists those links, and every other setting is still there.
4. `claude plugin validate ~\.claude\mods\<mod>` passes.
5. Start a new Claude Code session (terminal and desktop Code tab) and confirm the mod's band, pane or status entry appears. Inside WSL, check `/home/<user>/.claude/mods/<mod>` resolves through `/mnt/<drive>` and the WSL settings file carries the `:`-joined list.

## Related

- [AI module reference](../modules/ai.md) - `Deploy-AiMods`, `Deploy-AiMarketplaces`, `Update-AiMods`, `Get-AiModRoster`, `Resolve-AiModsConfig`, `Resolve-AiModsPluginDirs`, `Set-ClaudeSettingsEnv`, `Set-ClaudeSettingsKey`, `Test-AiModsCli`
- [Deploy-AiMods configuration guide](../configuration/guides/ai/Deploy-AiMods.md) - the `AiMods` keys, decision by decision
- [Deploy-AiMarketplaces configuration guide](../configuration/guides/ai/Deploy-AiMarketplaces.md) - the `AiMarketplaces` keys
- [Update-AiMods configuration guide](../configuration/guides/ai/Update-AiMods.md) - the `AiMods.Sources` keys
- [AI Skills](skills.md) - the same deployment model for Agent Skills
- [Troubleshooting - AI Mods Issues](../reference/troubleshooting.md#ai-mods-issues)
