# Third-Party Licenses

WinuX is released under the [MIT License](LICENSE). It bundles or builds on the
third-party components listed below. Each retains its own license; this file
collects the required notices.

If you add or remove vendored third-party content, update this file accordingly.

---

## Win11Debloat

- **Path in this repository:** `Windows/Win11Debloat/`
- **Upstream:** https://github.com/Raphire/Win11Debloat
- **Author:** Raphire
- **License:** MIT - the original license text is preserved at
  `Windows/Win11Debloat/vendor/LICENSE`. The pinned upstream version is recorded
  in `Windows/Win11Debloat/vendor/VENDORED_VERSION.txt`.

WinuX invokes Win11Debloat as a debloat backend; it is vendored unmodified.

---

## JetBrains Mono (Nerd Font patched)

- **Path in this repository:** `JetBrainsMonoNerdFont/`
- **Upstream font:** https://github.com/JetBrains/JetBrainsMono (JetBrains Mono)
- **Nerd Fonts patcher:** https://github.com/ryanoasis/nerd-fonts (Ryan L. McIntyre)
- **License:** SIL Open Font License, Version 1.1 (OFL-1.1) - the full license
  text is at `JetBrainsMonoNerdFont/OFL.txt`.
- **Copyright:** 2020 The JetBrains Mono Project Authors. Nerd Font glyph
  patches by the Nerd Fonts project.

The fonts are aggregated with (not merged into) WinuX and retain their OFL-1.1
license. Per OFL-1.1 §1, the license text ships alongside the font files.

---

## Oh My Posh (configured, not vendored)

- **Upstream:** https://github.com/JanDeDobbeleer/oh-my-posh
- **Author:** Jan De Dobbeleer
- **License:** MIT

WinuX ships only an Oh My Posh *theme/configuration* file, not the Oh My Posh
binary; the tool itself is installed from upstream during bootstrap. Listed here
as a courtesy acknowledgement.
