---
name: Bug report
about: Something does not work as expected (vous pouvez écrire en français)
title: "[Bug] "
labels: bug
assignees: ''
---

<!--
Thank you for taking the time to report a problem!
Vous pouvez remplir ce formulaire en français.
Please remove the lines that do not apply.
-->

### Versions

- **TruePlayed version** (Esc > Options > AddOns > TruePlayed, bottom of the page):
- **Game client**: WoW Forever / Classic Era
- **Client build**: paste the result of `/dump select(4, GetBuildInfo())`
- **Game language**: English / French / other:

### Other addons

List your other addons, especially **RXPGuides**, **WTFix**, a Data Broker display
(Titan Panel, ChocolateBar, ElvUI...) or a chat addon:

-

### What happened

**Steps to reproduce**

1.
2.
3.

**What I expected**

**What happened instead**

### Lua errors

Turn errors on with `/console scriptErrors 1`, then `/reload` and reproduce the problem.
Paste the full error text below, or attach the most recent file from the
`Errors` folder of your game installation (or the BugSack report if you use BugSack).

```
paste the error here
```

### Performance problem? (optional)

Paste the output of `/tpl perf` and wait 60 seconds for the "Tick:" line:

```
paste /tpl perf output here
```

### Screenshot (optional)

A screenshot of the bar, the tooltip (hold Shift for the detailed one) or the
statistics window often helps.
