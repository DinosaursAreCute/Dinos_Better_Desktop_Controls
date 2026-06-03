#!/usr/bin/env python3
"""
NEXUS — System Intelligence Dashboard
A real-time system monitor designed to complement Dino's desktop environment.

Install:  pip install customtkinter psutil matplotlib
Run:      python nexus_dashboard.py
"""

import tkinter as tk
import tkinter.ttk as ttk
import customtkinter as ctk
import psutil
import threading
import time
import datetime
import math
import platform
import socket
import sys
import os
from collections import deque

try:
    import matplotlib
    matplotlib.use("TkAgg")
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
    HAS_MPL = True
except ImportError:
    HAS_MPL = False

# ── Palette (matches the AHK script's #1a1a2e / #00d4ff scheme) ───────────────

BG      = "#0d0d1e"
SURFACE = "#1a1a2e"
CARD    = "#16213e"
CARD2   = "#0f1b35"
BORDER  = "#1e3a5f"
BORDER2 = "#2a4a7f"

CYAN    = "#00d4ff"   # matches the AHK toast exactly
PURPLE  = "#7b2fff"
GREEN   = "#00f5a0"
AMBER   = "#ffd166"
RED     = "#ff4757"
PINK    = "#e040fb"

WHITE   = "#f0f4ff"
GRAY    = "#7a8aaa"
DIM     = "#2a3a5a"

FONT    = "Segoe UI"   # Windows system font


# ── Ring Gauge ────────────────────────────────────────────────────────────────

class RingGauge(tk.Canvas):
    """Animated arc ring gauge drawn on a tk.Canvas."""

    ARC_START  = 225    # degrees, tkinter convention (counter-clockwise from east)
    ARC_SPAN   = 270    # total degrees the ring spans

    def __init__(self, master, size=130, fg=CYAN, bg_color=CARD,
                 label="", unit="%", **kw):
        super().__init__(master, width=size, height=size,
                         bg=bg_color, highlightthickness=0, **kw)
        self.S   = size
        self.fg  = fg
        self.lbl = label
        self.unit = unit
        self._bg_color = bg_color
        self._val    = 0.0
        self._target = 0.0
        self._anim   = False
        self._render()

    # ── public ────────────────────────────────────────────────────────────────

    def set_value(self, value: float, animate=True):
        self._target = max(0.0, min(100.0, value))
        if not animate:
            self._val = self._target
            self._render()
        elif not self._anim:
            self._tick()

    # ── private ───────────────────────────────────────────────────────────────

    def _tick(self):
        self._anim = True
        diff = self._target - self._val
        if abs(diff) < 0.4:
            self._val = self._target
            self._render()
            self._anim = False
            return
        self._val += diff * 0.22
        self._render()
        self.after(16, self._tick)   # ~60 fps

    def _hue(self):
        if self._val < 60:
            return self.fg
        if self._val < 80:
            return AMBER
        return RED

    def _render(self):
        self.delete("all")
        S   = self.S
        cx  = cy = S / 2
        pad = 14
        r   = S / 2 - pad
        lw  = 10

        # Track
        self._arc(cx, cy, r, self.ARC_START, self.ARC_SPAN, DIM, lw + 1)

        # Value arc
        if self._val > 0.1:
            sweep = (self._val / 100.0) * self.ARC_SPAN
            color = self._hue()
            self._arc(cx, cy, r, self.ARC_START, sweep, color, lw)
            # inner glow
            self._arc(cx, cy, r, self.ARC_START, sweep, color + "55", lw - 5)
            # endpoint dot
            self._dot(cx, cy, r, self.ARC_START - sweep, color)

        # Origin dot
        self._dot(cx, cy, r, self.ARC_START, DIM)

        # Value text
        self.create_text(cx, cy - 8,
                         text=f"{self._val:.0f}",
                         font=(FONT, 22, "bold"),
                         fill=WHITE, anchor="center")
        # Unit / label
        self.create_text(cx, cy + 14,
                         text=self.unit,
                         font=(FONT, 8),
                         fill=GRAY, anchor="center")

    def _arc(self, cx, cy, r, start, extent, color, width):
        x0, y0 = cx - r, cy - r
        x1, y1 = cx + r, cy + r
        self.create_arc(x0, y0, x1, y1,
                        start=start, extent=-extent,
                        style="arc", outline=color, width=width)

    def _dot(self, cx, cy, r, angle_deg, color):
        a = math.radians(angle_deg)
        x = cx + r * math.cos(a)
        y = cy - r * math.sin(a)
        dr = 5
        self.create_oval(x - dr, y - dr, x + dr, y + dr,
                         fill=color, outline="")


# ── Spark Line ────────────────────────────────────────────────────────────────

class SparkLine(tk.Canvas):
    """Mini 60-sample history sparkline."""

    SAMPLES = 60

    def __init__(self, master, width=160, height=40,
                 color=CYAN, bg_color=CARD, **kw):
        super().__init__(master, width=width, height=height,
                         bg=bg_color, highlightthickness=0, **kw)
        self.W, self.H = width, height
        self.color = color
        self._data: deque = deque([0.0] * self.SAMPLES, maxlen=self.SAMPLES)

    def push(self, value: float):
        self._data.append(max(0.0, min(100.0, value)))
        self._render()

    def _render(self):
        self.delete("all")
        data = list(self._data)
        n    = len(data)
        if n < 2:
            return
        W, H, pad = self.W, self.H, 3

        def px(i):   return pad + i / (n - 1) * (W - 2 * pad)
        def py(v):   return H - pad - (v / 100) * (H - 2 * pad)

        # Fill area
        poly = [pad, H]
        for i, v in enumerate(data):
            poly += [px(i), py(v)]
        poly += [px(n - 1), H]
        self.create_polygon(poly, fill=self.color + "22", outline="")

        # Line
        pts = []
        for i, v in enumerate(data):
            pts += [px(i), py(v)]
        self.create_line(pts, fill=self.color, width=1.5, smooth=True)

        # Latest dot
        lv = data[-1]
        self.create_oval(px(n-1)-3, py(lv)-3,
                         px(n-1)+3, py(lv)+3,
                         fill=self.color, outline="")


# ── Metric Card ───────────────────────────────────────────────────────────────

class MetricCard(ctk.CTkFrame):
    """A single metric panel: header, ring gauge, sparkline, and stat rows."""

    def __init__(self, master, title: str, icon: str,
                 gauge_color=CYAN, unit="%", **kw):
        super().__init__(master,
                         fg_color=CARD,
                         corner_radius=14,
                         border_width=1,
                         border_color=BORDER,
                         **kw)

        # ── Header ────────────────────────────────────────────────────────────
        hdr = ctk.CTkFrame(self, fg_color="transparent")
        hdr.pack(fill="x", padx=16, pady=(14, 0))

        ctk.CTkLabel(hdr, text=icon, font=(FONT, 16),
                     text_color=gauge_color).pack(side="left")
        ctk.CTkLabel(hdr, text=f"  {title}",
                     font=(FONT, 10, "bold"),
                     text_color=WHITE).pack(side="left")

        # Subtle live indicator
        self._live_dot = ctk.CTkLabel(hdr, text="●", font=(FONT, 8),
                                      text_color=gauge_color)
        self._live_dot.pack(side="right")

        # ── Gauge ─────────────────────────────────────────────────────────────
        self.gauge = RingGauge(self, size=128, fg=gauge_color,
                               bg_color=CARD, unit=unit)
        self.gauge.pack(pady=6)

        # ── Sparkline ─────────────────────────────────────────────────────────
        self.spark = SparkLine(self, width=160, height=36,
                               color=gauge_color, bg_color=CARD)
        self.spark.pack(pady=(0, 6))

        # ── Stats grid ────────────────────────────────────────────────────────
        self._stats_frame = ctk.CTkFrame(self, fg_color="transparent")
        self._stats_frame.pack(fill="x", padx=16, pady=(0, 14))
        self._stat_labels: dict[str, ctk.CTkLabel] = {}

    def add_stat(self, key: str, label: str):
        row = ctk.CTkFrame(self._stats_frame, fg_color="transparent")
        row.pack(fill="x", pady=1)
        ctk.CTkLabel(row, text=label, font=(FONT, 9),
                     text_color=GRAY).pack(side="left")
        val = ctk.CTkLabel(row, text="—", font=(FONT, 9, "bold"),
                           text_color=WHITE)
        val.pack(side="right")
        self._stat_labels[key] = val

    def set_stat(self, key: str, text: str):
        if key in self._stat_labels:
            self._stat_labels[key].configure(text=text)

    def set_value(self, v: float):
        self.gauge.set_value(v)
        self.spark.push(v)


# ── Main Application ──────────────────────────────────────────────────────────

class NexusDashboard(ctk.CTk):

    REFRESH_MS = 1000   # data refresh interval

    def __init__(self):
        super().__init__()

        # ── Window setup ──────────────────────────────────────────────────────
        self.title("NEXUS — System Intelligence")
        self.geometry("1160x740")
        self.minsize(960, 620)
        self.configure(fg_color=BG)
        self._set_titlebar_dark()

        # ── State ─────────────────────────────────────────────────────────────
        self._cpu_history: deque = deque([0.0] * 60, maxlen=60)
        self._net_prev    = psutil.net_io_counters()
        self._net_time    = time.monotonic()
        self._proc_cache: list  = []
        self._updating    = False
        self._running     = True

        # ── Build UI ──────────────────────────────────────────────────────────
        self._build_header()
        self._build_metrics_row()
        self._build_bottom()

        # ── Start refresh loop ────────────────────────────────────────────────
        self.after(200, self._schedule)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── Window helpers ────────────────────────────────────────────────────────

    def _set_titlebar_dark(self):
        """Apply dark titlebar on Windows 10/11."""
        try:
            import ctypes
            HWND = self.winfo_id()
            DWMWA_USE_IMMERSIVE_DARK_MODE = 20
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                HWND, DWMWA_USE_IMMERSIVE_DARK_MODE,
                ctypes.byref(ctypes.c_int(1)), ctypes.sizeof(ctypes.c_int))
            # Round corners
            DWMWA_WINDOW_CORNER_PREFERENCE = 33
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                HWND, DWMWA_WINDOW_CORNER_PREFERENCE,
                ctypes.byref(ctypes.c_int(2)), ctypes.sizeof(ctypes.c_int))
        except Exception:
            pass

    def _on_close(self):
        self._running = False
        self.destroy()

    # ── UI: Header ────────────────────────────────────────────────────────────

    def _build_header(self):
        hdr = ctk.CTkFrame(self, fg_color=SURFACE, corner_radius=0,
                           height=68, border_width=0)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)

        inner = ctk.CTkFrame(hdr, fg_color="transparent")
        inner.pack(fill="both", expand=True, padx=24, pady=0)

        # Animated hex logo
        self._logo_canvas = tk.Canvas(inner, width=42, height=42,
                                      bg=SURFACE, highlightthickness=0)
        self._logo_canvas.pack(side="left", pady=13)
        self._draw_hex_logo()
        self._start_logo_pulse()

        # Title
        ctk.CTkLabel(inner, text="NEXUS",
                     font=(FONT, 22, "bold"),
                     text_color=WHITE).pack(side="left", padx=(8, 0))
        ctk.CTkLabel(inner, text="  ·  SYSTEM INTELLIGENCE",
                     font=(FONT, 9),
                     text_color=GRAY).pack(side="left", pady=(8, 0))

        # Divider
        div = ctk.CTkFrame(inner, width=1, height=28, fg_color=BORDER)
        div.pack(side="left", padx=20, pady=20)

        # System info
        try:
            hostname = socket.gethostname()
        except Exception:
            hostname = "localhost"
        os_str = f"{platform.system()} {platform.release()}"
        ctk.CTkLabel(inner,
                     text=f"{hostname}  ·  {os_str}",
                     font=(FONT, 10),
                     text_color=GRAY).pack(side="left")

        # Right: status + clock
        right = ctk.CTkFrame(inner, fg_color="transparent")
        right.pack(side="right")

        self._status_dot = ctk.CTkLabel(right, text="●", font=(FONT, 11),
                                        text_color=GREEN)
        self._status_dot.pack(side="left", padx=(0, 8))

        self._clock_var = tk.StringVar(value="——:——:——")
        ctk.CTkLabel(right, textvariable=self._clock_var,
                     font=(FONT, 16, "bold"),
                     text_color=WHITE).pack(side="left")

        self._date_var = tk.StringVar(value="")
        ctk.CTkLabel(right, textvariable=self._date_var,
                     font=(FONT, 9),
                     text_color=GRAY).pack(side="right", padx=(0, 4))

        # Bottom accent line
        accent = tk.Canvas(hdr, height=2, bg=SURFACE, highlightthickness=0)
        accent.pack(fill="x", side="bottom")
        accent.bind("<Configure>",
                    lambda e: self._draw_accent_line(accent, e.width))

    def _draw_hex_logo(self):
        c = self._logo_canvas
        cx, cy, r = 21, 21, 16
        pts = []
        for i in range(6):
            a = math.radians(60 * i - 30)
            pts += [cx + r * math.cos(a), cy + r * math.sin(a)]
        c.delete("hex")
        c.create_polygon(pts, outline=CYAN, fill="", width=2, tags="hex")
        c.create_text(cx, cy, text="N", font=(FONT, 11, "bold"),
                      fill=CYAN, tags="hex")

    def _start_logo_pulse(self):
        self._logo_alpha = 0
        self._logo_dir   = 1
        self._pulse_logo()

    def _pulse_logo(self):
        if not self._running:
            return
        self._logo_alpha += self._logo_dir * 4
        if self._logo_alpha >= 255:
            self._logo_alpha = 255
            self._logo_dir = -1
        elif self._logo_alpha <= 80:
            self._logo_alpha = 80
            self._logo_dir = 1
        hex_val = f"{self._logo_alpha:02x}"
        color = f"#00{hex_val}ff"
        self._logo_canvas.itemconfigure("hex", outline=color, fill="")
        self.after(30, self._pulse_logo)

    def _draw_accent_line(self, canvas, width):
        canvas.delete("all")
        # Gradient from PURPLE to CYAN
        steps = max(1, width // 2)
        for i in range(steps):
            t  = i / steps
            r  = int(0x7b + t * (0x00 - 0x7b))
            g  = int(0x2f + t * (0xd4 - 0x2f))
            b  = int(0xff + t * (0xff - 0xff))
            col = f"#{r:02x}{g:02x}{b:02x}"
            x  = i * (width / steps)
            canvas.create_line(x, 0, x + width / steps + 1, 0,
                               fill=col, width=2)

    # ── UI: Metrics row ───────────────────────────────────────────────────────

    def _build_metrics_row(self):
        row = ctk.CTkFrame(self, fg_color="transparent")
        row.pack(fill="x", padx=16, pady=(14, 6))

        # CPU card
        self.cpu_card = MetricCard(row, "CPU", "⚡", CYAN, unit="% LOAD")
        self.cpu_card.pack(side="left", fill="both", expand=True, padx=(0, 6))
        self.cpu_card.add_stat("cores",  "Cores")
        self.cpu_card.add_stat("freq",   "Clock")
        self.cpu_card.add_stat("model",  "Model")

        # RAM card
        self.ram_card = MetricCard(row, "MEMORY", "◈", PURPLE, unit="% USED")
        self.ram_card.pack(side="left", fill="both", expand=True, padx=6)
        self.ram_card.add_stat("used",   "Used")
        self.ram_card.add_stat("free",   "Available")
        self.ram_card.add_stat("total",  "Total")

        # Disk card
        self.disk_card = MetricCard(row, "DISK", "◉", GREEN, unit="% FULL")
        self.disk_card.pack(side="left", fill="both", expand=True, padx=6)
        self.disk_card.add_stat("used",  "Used")
        self.disk_card.add_stat("free",  "Free")
        self.disk_card.add_stat("total", "Total")

        # Network card
        self.net_card = MetricCard(row, "NETWORK", "⬡", AMBER, unit="KB/s")
        self.net_card.pack(side="left", fill="both", expand=True, padx=(6, 0))
        self.net_card.add_stat("up",    "↑ Upload")
        self.net_card.add_stat("down",  "↓ Download")
        self.net_card.add_stat("total", "Session")

    # ── UI: Bottom (chart + process list) ─────────────────────────────────────

    def _build_bottom(self):
        bottom = ctk.CTkFrame(self, fg_color="transparent")
        bottom.pack(fill="both", expand=True, padx=16, pady=(0, 16))

        self._build_cpu_chart(bottom)
        self._build_process_list(bottom)

    def _build_cpu_chart(self, parent):
        card = ctk.CTkFrame(parent, fg_color=CARD, corner_radius=14,
                            border_width=1, border_color=BORDER)
        card.pack(side="left", fill="both", expand=True, padx=(0, 8))

        hdr = ctk.CTkFrame(card, fg_color="transparent")
        hdr.pack(fill="x", padx=18, pady=(14, 4))
        ctk.CTkLabel(hdr, text="▸  CPU HISTORY",
                     font=(FONT, 10, "bold"), text_color=WHITE).pack(side="left")
        self._avg_label = ctk.CTkLabel(hdr, text="60s avg  —",
                                       font=(FONT, 9), text_color=GRAY)
        self._avg_label.pack(side="right")

        chart_holder = ctk.CTkFrame(card, fg_color="transparent")
        chart_holder.pack(fill="both", expand=True, padx=10, pady=(0, 12))

        if HAS_MPL:
            self._fig = Figure(facecolor=CARD, dpi=90)
            self._ax  = self._fig.add_subplot(111)
            self._style_ax()
            self._mpl_canvas = FigureCanvasTkAgg(self._fig, master=chart_holder)
            self._mpl_canvas.get_tk_widget().configure(bg=CARD,
                                                       highlightthickness=0)
            self._mpl_canvas.get_tk_widget().pack(fill="both", expand=True)
        else:
            # Fallback: big sparkline
            self._big_spark = SparkLine(chart_holder, width=400, height=180,
                                        color=CYAN, bg_color=CARD)
            self._big_spark.pack(fill="both", expand=True)

    def _style_ax(self):
        ax = self._ax
        ax.set_facecolor(CARD)
        self._fig.patch.set_facecolor(CARD)
        for sp in ax.spines.values():
            sp.set_edgecolor(BORDER)
        ax.tick_params(colors=GRAY, labelsize=7, length=0)
        ax.set_ylim(0, 100)
        ax.set_xlim(0, 59)
        ax.set_ylabel("CPU %", color=GRAY, fontsize=7, labelpad=4)
        ax.grid(True, color=BORDER, linewidth=0.4, alpha=0.7)
        ax.set_xticks([0, 15, 30, 45, 59])
        ax.set_xticklabels(["60s", "45s", "30s", "15s", "now"], fontsize=7,
                            color=GRAY)

    def _update_cpu_chart(self):
        if not HAS_MPL:
            for v in list(self._cpu_history):
                self._big_spark.push(v)
            return

        data = list(self._cpu_history)
        x    = list(range(len(data)))

        self._ax.clear()
        self._style_ax()

        # Area fill with gradient effect
        self._ax.fill_between(x, data, alpha=0.12, color=CYAN)
        self._ax.fill_between(x, data, alpha=0.06, color=PURPLE)

        # Main line
        self._ax.plot(x, data, color=CYAN, linewidth=2,
                      solid_capstyle="round", solid_joinstyle="round")

        # Current value dot + horizontal reference
        if data:
            last = data[-1]
            self._ax.scatter([x[-1]], [last], color=CYAN, s=30, zorder=5)
            self._ax.axhline(last, color=CYAN, linewidth=0.6,
                             alpha=0.35, linestyle="--")
            self._ax.text(58, last + 3, f"{last:.0f}%",
                          color=CYAN, fontsize=7, ha="right", va="bottom")

        self._fig.tight_layout(pad=0.6)
        self._mpl_canvas.draw_idle()

        # Update average label
        avg = sum(data) / len(data) if data else 0
        self._avg_label.configure(text=f"60s avg  {avg:.1f}%")

    def _build_process_list(self, parent):
        card = ctk.CTkFrame(parent, fg_color=CARD, corner_radius=14,
                            border_width=1, border_color=BORDER, width=360)
        card.pack(side="right", fill="both", expand=True, padx=(8, 0))
        card.pack_propagate(False)

        hdr = ctk.CTkFrame(card, fg_color="transparent")
        hdr.pack(fill="x", padx=18, pady=(14, 8))

        ctk.CTkLabel(hdr, text="▸  TOP PROCESSES",
                     font=(FONT, 10, "bold"), text_color=WHITE).pack(side="left")

        self._search_var = tk.StringVar()
        self._search_var.trace_add("write", lambda *_: self._filter_procs())
        search = ctk.CTkEntry(
            hdr, textvariable=self._search_var,
            placeholder_text="filter…", width=110, height=26,
            font=(FONT, 10), fg_color=CARD2, border_color=BORDER,
            text_color=WHITE, placeholder_text_color=GRAY,
        )
        search.pack(side="right")

        # ── Treeview ──────────────────────────────────────────────────────────
        tree_wrap = ctk.CTkFrame(card, fg_color="transparent")
        tree_wrap.pack(fill="both", expand=True, padx=12, pady=(0, 12))

        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Nexus.Treeview",
                        background=CARD,
                        foreground=WHITE,
                        fieldbackground=CARD,
                        rowheight=26,
                        font=(FONT, 9),
                        borderwidth=0,
                        relief="flat")
        style.configure("Nexus.Treeview.Heading",
                        background=CARD2,
                        foreground=GRAY,
                        font=(FONT, 8, "bold"),
                        relief="flat",
                        borderwidth=0)
        style.map("Nexus.Treeview",
                  background=[("selected", "#1e3a6e")],
                  foreground=[("selected", CYAN)])
        style.layout("Nexus.Treeview", [
            ("Nexus.Treeview.treearea", {"sticky": "nswe"})
        ])

        cols = ("name", "pid", "cpu", "mem")
        self._tree = ttk.Treeview(tree_wrap, columns=cols, show="headings",
                                  style="Nexus.Treeview", selectmode="browse")
        self._tree.heading("name", text="Process",
                           command=lambda: self._sort_procs("name"))
        self._tree.heading("pid",  text="PID",
                           command=lambda: self._sort_procs("pid"))
        self._tree.heading("cpu",  text="CPU %",
                           command=lambda: self._sort_procs("cpu"))
        self._tree.heading("mem",  text="Memory",
                           command=lambda: self._sort_procs("mem"))
        self._tree.column("name", width=165, anchor="w", stretch=True)
        self._tree.column("pid",  width=55,  anchor="center", stretch=False)
        self._tree.column("cpu",  width=55,  anchor="center", stretch=False)
        self._tree.column("mem",  width=70,  anchor="center", stretch=False)

        # Tag-based row striping
        self._tree.tag_configure("even", background=CARD)
        self._tree.tag_configure("odd",  background=CARD2)
        self._tree.tag_configure("high", foreground=RED)
        self._tree.tag_configure("med",  foreground=AMBER)

        vsb = ttk.Scrollbar(tree_wrap, orient="vertical",
                            command=self._tree.yview)
        style.configure("Nexus.Vertical.TScrollbar",
                        background=BORDER, troughcolor=CARD,
                        arrowcolor=GRAY, borderwidth=0)
        vsb.configure(style="Nexus.Vertical.TScrollbar")
        self._tree.configure(yscrollcommand=vsb.set)

        self._tree.pack(side="left", fill="both", expand=True)
        vsb.pack(side="right", fill="y")

        self._proc_data: list = []
        self._sort_key = "cpu"
        self._sort_rev = True

    # ── Data refresh ──────────────────────────────────────────────────────────

    def _schedule(self):
        if not self._running:
            return
        threading.Thread(target=self._collect, daemon=True).start()
        self.after(self.REFRESH_MS, self._schedule)

    def _collect(self):
        """Gather all metrics in a background thread."""
        cpu_pct  = psutil.cpu_percent(interval=0.5)
        cpu_freq = psutil.cpu_freq()
        cpu_lc   = psutil.cpu_count(logical=True)
        cpu_pc   = psutil.cpu_count(logical=False) or 1

        ram  = psutil.virtual_memory()

        try:
            disk = psutil.disk_usage("C:\\" if sys.platform == "win32" else "/")
        except Exception:
            disk = psutil.disk_usage("/")

        net_now  = psutil.net_io_counters()
        net_time = time.monotonic()
        elapsed  = net_time - self._net_time
        if elapsed > 0.01:
            up_bps   = (net_now.bytes_sent - self._net_prev.bytes_sent) / elapsed
            down_bps = (net_now.bytes_recv - self._net_prev.bytes_recv) / elapsed
        else:
            up_bps = down_bps = 0.0
        self._net_prev = net_now
        self._net_time = net_time

        # CPU model name
        cpu_name = self._get_cpu_name()

        # Processes
        procs = []
        for p in psutil.process_iter(["name", "pid", "cpu_percent",
                                      "memory_info"], ad_value=None):
            try:
                n  = p.info["name"] or "?"
                pid = p.info["pid"]
                c  = p.info["cpu_percent"] or 0.0
                m  = (p.info["memory_info"].rss / 1048576
                      if p.info["memory_info"] else 0.0)
                procs.append((n, pid, c, m))
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass

        procs.sort(key=lambda x: x[2], reverse=True)

        # Push to main thread
        self.after(0, lambda: self._apply(
            cpu_pct, cpu_freq, cpu_lc, cpu_pc, cpu_name,
            ram, disk,
            up_bps, down_bps, net_now,
            procs,
        ))

    @staticmethod
    def _get_cpu_name() -> str:
        try:
            import winreg
            k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                               r"HARDWARE\DESCRIPTION\System\CentralProcessor\0")
            name = winreg.QueryValueEx(k, "ProcessorNameString")[0].strip()
            winreg.CloseKey(k)
            return name
        except Exception:
            pass
        raw = platform.processor()
        return raw[:28] + "…" if len(raw) > 28 else raw or "Unknown CPU"

    def _apply(self, cpu_pct, cpu_freq, cpu_lc, cpu_pc, cpu_name,
               ram, disk, up_bps, down_bps, net_now, procs):
        """Apply gathered data to all widgets — must run on the main thread."""
        if not self._running:
            return

        # Clock
        now = datetime.datetime.now()
        self._clock_var.set(now.strftime("%H:%M:%S"))
        self._date_var.set(now.strftime("%A, %d %b %Y"))

        # ── CPU ───────────────────────────────────────────────────────────────
        self.cpu_card.set_value(cpu_pct)
        self._cpu_history.append(cpu_pct)
        freq_str = (f"{cpu_freq.current / 1000:.2f} GHz"
                    if cpu_freq else "—")
        model_short = cpu_name[:20] + "…" if len(cpu_name) > 20 else cpu_name
        self.cpu_card.set_stat("cores", f"{cpu_pc}P / {cpu_lc}L")
        self.cpu_card.set_stat("freq",  freq_str)
        self.cpu_card.set_stat("model", model_short)
        self._update_cpu_chart()

        # ── RAM ───────────────────────────────────────────────────────────────
        self.ram_card.set_value(ram.percent)
        self.ram_card.set_stat("used",  self._fmt_bytes(ram.used))
        self.ram_card.set_stat("free",  self._fmt_bytes(ram.available))
        self.ram_card.set_stat("total", self._fmt_bytes(ram.total))

        # ── Disk ──────────────────────────────────────────────────────────────
        self.disk_card.set_value(disk.percent)
        self.disk_card.set_stat("used",  self._fmt_bytes(disk.used))
        self.disk_card.set_stat("free",  self._fmt_bytes(disk.free))
        self.disk_card.set_stat("total", self._fmt_bytes(disk.total))

        # ── Network ───────────────────────────────────────────────────────────
        total_kbs = (up_bps + down_bps) / 1024
        # Scale: 1 MB/s = 100% fill
        net_pct = min(100.0, total_kbs / 1024 * 100)
        self.net_card.set_value(net_pct)
        self.net_card.set_stat("up",   f"{up_bps   / 1024:>7.1f} KB/s")
        self.net_card.set_stat("down", f"{down_bps  / 1024:>7.1f} KB/s")
        sent_gb = net_now.bytes_sent / 1e9
        recv_gb = net_now.bytes_recv / 1e9
        self.net_card.set_stat("total",
                               f"↑{sent_gb:.2f}  ↓{recv_gb:.2f} GB")

        # ── Processes ─────────────────────────────────────────────────────────
        self._proc_data = procs
        self._filter_procs()

    # ── Process list helpers ──────────────────────────────────────────────────

    def _sort_procs(self, key: str):
        idx = {"name": 0, "pid": 1, "cpu": 2, "mem": 3}[key]
        if self._sort_key == key:
            self._sort_rev = not self._sort_rev
        else:
            self._sort_key = key
            self._sort_rev = (key in ("cpu", "mem"))
        self._proc_data.sort(key=lambda x: x[idx], reverse=self._sort_rev)
        self._filter_procs()

    def _filter_procs(self):
        q = self._search_var.get().lower()
        self._tree.delete(*self._tree.get_children())

        count = 0
        for i, (name, pid, cpu, mem) in enumerate(self._proc_data):
            if q and q not in name.lower():
                continue

            tags = ["even" if i % 2 == 0 else "odd"]
            if cpu >= 20:
                tags.append("high")
            elif cpu >= 5:
                tags.append("med")

            self._tree.insert(
                "", "end",
                values=(
                    name[:26],
                    pid,
                    f"{cpu:.1f}",
                    f"{mem:.0f} MB",
                ),
                tags=tags,
            )
            count += 1
            if count >= 60:
                break

    # ── Utilities ─────────────────────────────────────────────────────────────

    @staticmethod
    def _fmt_bytes(n: int) -> str:
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if n < 1024:
                return f"{n:.1f} {unit}"
            n /= 1024
        return f"{n:.1f} PB"


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    ctk.set_appearance_mode("dark")
    ctk.set_default_color_theme("dark-blue")
    app = NexusDashboard()
    app.mainloop()


if __name__ == "__main__":
    main()
