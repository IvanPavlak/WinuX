<p align="center">
  <img width="359" height="440" alt="WinuX" src="https://github.com/user-attachments/assets/54344fab-c731-4f3a-92f4-62bcbd3e3ac4" />
</p>

<h1 align="center">WinuX</h1>

<p align="center"><strong>Windows 11, the Linux way</strong></p>

<p align="center">
A comprehensive PowerShell-based dotfiles system that turns a fresh Windows 11 install into a highly automated, fully personalized power-user environment - in a single command.
</p>

---

> **Today** WinuX is a terminal/keyboard-driven system built for power users. **The goal** is to make
> it accessible to _everyone_ - a guided installer and a GUI are on the [roadmap](docs/roadmap.md) -
> without ever taking away the deep configurability that defines it.

---

## What it does

From one bootstrap command or a simple executable, all driven by a single configuration file, across as many machines as you own:

- **One-command bootstrap** - fresh Windows to a fully configured environment in a single line.
- **Multi-machine** - manage every machine from one configuration; machines can share an identical setup or each define their own.
- **Package management** - install software via WinGet, Scoop, and/or Chocolatey.
- **Dotfiles management** - symlink every config so the system behaves exactly as you want.
- **Repository orchestration** - clone and update all your repositories with one command.
- **Workflow automation** - open and position entire workspaces across monitors and virtual desktops.
- **System theming** - one-command, multi-monitor theme and wallpaper setup.
- **Machine-type profiles** - hostname-detected machine types give each machine the right subset of apps, layouts, and settings.
- **WSL provisioning** - optional, config-gated WSL/Ubuntu setup with a themed shell.
- **Idempotent by design** - every step is safe to re-run, so the bootstrap doubles as repair.
- **Tested and documented** - the full Pester suite runs in CI, and every function has a man-style reference in the docs.

## Documentation

**The documentation is the single source of truth for WinuX** - installation, configuration, every
module, and a man-style reference for every PowerShell function (each linked to its source).

**Read it live at [ivanpavlak.github.io/WinuX](https://ivanpavlak.github.io/WinuX/)** - or browse it
in this repository under [**`docs/`**](docs/README.md), or serve the site locally:

```powershell
# From the repository root
npx docsify-cli serve docs
```

## License

WinuX is released under the [MIT License](LICENSE).

### Third-party components

This repository builds on the following, each under its own license
(see [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md)):

| Component                                              | Author                       | License      |
| ------------------------------------------------------ | ---------------------------- | ------------ |
| Win11Debloat (`Windows/Win11Debloat/`)                 | Raphire                      | MIT          |
| JetBrains Mono / Nerd Fonts (`JetBrainsMonoNerdFont/`) | JetBrains / Ryan L. McIntyre | SIL OFL 1.1  |
| Oh My Posh (configured, not vendored)                  | Jan De Dobbeleer             | MIT          |

## Contributing

Contributions of all kinds are welcome - code, docs, tests, bug reports, and ideas. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) first. For security
issues, follow [SECURITY.md](SECURITY.md).

---

## Supporters

WinuX is free and open-source. If it saves you time, please consider supporting it.

<p align="center">
  <a href="https://ko-fi.com/ivanpavlak"><img src="https://img.shields.io/badge/Ko--fi-Support%20WinuX-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-fi"/></a>
  <a href="https://github.com/sponsors/IvanPavlak"><img src="https://img.shields.io/badge/GitHub%20Sponsors-Sponsor-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="GitHub Sponsors"/></a>
</p>

___

## Disclaimer

AI was used throughout this project and is ingrained in it - but everything has been manually
tested many times, over a long period, on multiple machines (VMware VMs, a personal PC, and
personal and work laptops). Regardless, use it at your own discretion.

Known problems and their workarounds live in [Known Issues](docs/reference/known-issues.md).
