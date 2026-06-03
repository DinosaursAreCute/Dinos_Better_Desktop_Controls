# Dinos_Better_Desktop_Controls
A collection of tools to make Windows feel faster and smarter.

---

## Workspaces — AutoHotkey

A small AHK script to switch virtual desktops via `Win + number` keys.

| Shortcut | Action |
| --- | --- |
| `Win + 1` … `Win + 9` | Switch to workspace 1–9 |
| `Win + Shift + 1` … `Win + Shift + 9` | Move active window to workspace 1–9 |

Requires [AutoHotkey v2](https://www.autohotkey.com/) and `VirtualDesktopAccessor.dll` (included).

---

## NEXUS — System Intelligence Dashboard

A real-time system monitoring dashboard with a polished dark UI that matches the desktop color scheme.

![NEXUS dashboard preview](https://i.imgur.com/placeholder.png)

**Features**
- Animated ring gauges for CPU, RAM, Disk, and Network
- 60-second CPU history chart
- Live process explorer with search and column sorting
- Smooth animations running at ~60 fps
- Dark titlebar and rounded corners on Windows 11
- Gradient accent line that transitions from purple → cyan (matching the AHK toast)

**Requirements**

```
Python 3.9+
pip install customtkinter psutil matplotlib
```

**Run**

```batch
cd nexus
run.bat
```

or directly:

```bash
python nexus/nexus_dashboard.py
```
