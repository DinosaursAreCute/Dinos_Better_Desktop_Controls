#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
ProcessSetPriority "High"

; =====================================================================
;  CommandBar  -  a PowerToys-Run style launcher, native AutoHotkey v2
;  Hotkey:  Ctrl + Alt + Space
;
;  Features
;    - Search & launch installed programs (Start Menu + Desktop)
;    - Run OS operations (lock, sleep, shutdown, restart, recycle bin...)
;    - Open Windows Settings pages by name
;    - Inline calculator (type a math expression)
;    - Open URLs / web search fallback
;    - Run shell commands         (prefix with  >  )
;    - Open files & folders by path
;  Navigation:  Up/Down move, Enter run, Shift+Enter run as admin (apps),
;               Esc / focus-loss hides the bar.
; =====================================================================

; ---------------------- configuration --------------------------------
BAR_W      := 720
BAR_FONT   := "Segoe UI"
COL_BG     := "1E1E1E"
COL_INPUT  := "2B2B2B"
COL_TEXT   := "FFFFFF"
MAX_RESULTS := 12

; ---------------------- global state ---------------------------------
global gApps := []          ; array of Maps: name, path, target
global gResults := []       ; current displayed result objects
global gIconCache := Map()  ; path -> system image list index
global gCatIcon := Map()    ; category -> icon index

; ---------------------- build the GUI --------------------------------
global Bar := Gui("-Caption +AlwaysOnTop +ToolWindow +Border")
Bar.BackColor := COL_BG
Bar.MarginX := 0, Bar.MarginY := 0

; -0x4 removes ES_MULTILINE so the input is a clean single line (no scrollbar)
global SB := Bar.Add("Edit", Format("x10 y10 w{} h36 -E0x200 -0x4 -VScroll -HScroll Background{} c{}", BAR_W-20, COL_INPUT, COL_TEXT))
SB.SetFont("s16", BAR_FONT)
SB.OnEvent("Change", (*) => UpdateResults())

global LV := Bar.Add("ListView", Format("x10 y58 w{} h360 -Hdr -Multi +LV0x10000 Background{} c{}", BAR_W-20, COL_BG, COL_TEXT)
    , ["Name", "Detail"])
LV.SetFont("s11", BAR_FONT)
LV.OnEvent("DoubleClick", (*) => RunSelected())
LV.ModifyCol(1, 340)              ; Name (icon shows in this first column)
LV.ModifyCol(2, BAR_W - 380)     ; Detail

; system small-icon image list so file/app icons look native
AttachSystemImageList(LV.Hwnd)
PrecacheCategoryIcons()

; ---------------------- index applications ---------------------------
ScanApps()

; ---------------------- tray menu ------------------------------------
A_TrayMenu.Delete()
A_TrayMenu.Add("Show Command Bar`tCtrl+Alt+Space", (*) => ShowBar())
A_TrayMenu.Add("Re-scan apps", (*) => ScanApps())
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show Command Bar`tCtrl+Alt+Space"
TraySetIcon("shell32.dll", 25)

; ---------------------- the hotkey -----------------------------------
^!Space:: ToggleBar()

ToggleBar() {
    if WinActive("ahk_id " Bar.Hwnd)
        Bar.Hide()
    else
        ShowBar()
}

ShowBar() {
    global gResults
    SB.Value := ""
    LV.Delete()
    gResults := []
    ; centre horizontally on the primary monitor, ~22% from the top
    x := (A_ScreenWidth - BAR_W) // 2
    y := A_ScreenHeight // 5
    Bar.Show(Format("x{} y{} w{} AutoSize NoActivate", x, y, BAR_W))
    Bar.Show()                 ; activate
    SB.Focus()
}

HideBar() {
    Bar.Hide()
}

; ---- hide when the bar loses focus ----------------------------------
OnMessage(0x06, OnActivate)      ; WM_ACTIVATE
OnActivate(wParam, lParam, msg, hwnd) {
    if (hwnd = Bar.Hwnd && (wParam & 0xFFFF) = 0)   ; WA_INACTIVE
        HideBar()
}

; ---- keyboard navigation, active only while the bar is focused ------
#HotIf WinActive("ahk_id " Bar.Hwnd)
Up::      MoveSel(-1)
Down::    MoveSel(1)
*Enter::  RunSelected()
Tab::     CompleteOrMove()
Escape::  HideBar()
#HotIf

MoveSel(dir) {
    cnt := LV.GetCount()
    if !cnt
        return
    cur := LV.GetNext(0)
    if !cur
        cur := dir > 0 ? 0 : 1
    next := cur + dir
    if (next < 1)
        next := cnt
    else if (next > cnt)
        next := 1
    LV.Modify(0, "-Select")
    LV.Modify(next, "Select Focus Vis")
}

CompleteOrMove() {
    MoveSel(1)
}

RunSelected() {
    row := LV.GetNext(0)
    if !row
        row := 1
    if (row < 1 || row > gResults.Length)
        return
    res := gResults[row]
    admin := GetKeyState("Shift", "P")
    HideBar()
    try ExecuteResult(res, admin)
    catch as e
        TrayTip "CommandBar", "Could not run: " e.Message, 1
}

; =====================================================================
;  Result building
; =====================================================================
UpdateResults() {
    global gResults
    q := Trim(SB.Value)
    gResults := []
    LV.Delete()
    if (q = "")
        return

    ; 1) shell command:  > ipconfig
    if (SubStr(q, 1, 1) = ">") {
        cmd := Trim(SubStr(q, 2))
        if (cmd != "")
            AddResult("shell", "Run command:  " cmd, "cmd /c  -  output stays open", cmd, gCatIcon["shell"])
    }

    ; 2) calculator
    val := TryCalc(q)
    if (val != "")
        AddResult("calc", q " = " val, "Enter to copy result to clipboard", val, gCatIcon["calc"])

    ; 3) explicit path (file or folder)
    if (FileExist(q)) {
        isDir := InStr(FileExist(q), "D")
        AddResult(isDir ? "folder" : "file", q, isDir ? "Open folder" : "Open file"
            , q, isDir ? gCatIcon["folder"] : GetIcon(q))
    }

    ; 4) URL
    if (IsUrl(q))
        AddResult("url", "Open  " q, "Open in default browser", NormalizeUrl(q), gCatIcon["web"])

    ; 5) OS operations, Settings pages, and applications compete on one
    ;    ranked list so the best match (whatever its kind) floats to the top.
    matches := []
    for cmd in OsCommands() {
        s := Score(cmd["title"], q)
        if KeywordMatch(cmd["keys"], q)        ; keyword hit is a strong signal
            s := Max(s, 600)
        if (s >= 0)
            matches.Push({s: s, type: "os", item: cmd})
    }
    for app in gApps {
        s := Score(app["name"], q)
        if (s >= 0)
            matches.Push({s: s, type: "app", item: app})
    }
    SortByScore(matches)
    for m in matches {
        if (gResults.Length >= MAX_RESULTS - 1)
            break
        if (m.type = "os") {
            c := m.item
            AddResult("os", c["title"], c["sub"], c["run"], gCatIcon["os"])
        } else {
            a := m.item
            icon := a.Has("target") && a["target"] ? GetIcon(a["target"])
                  : (a.Has("uwp") ? gCatIcon["app"] : GetIcon(a["path"]))
            AddResult("app", a["name"], a["path"], a, icon)
        }
    }

    ; 6) web-search fallback (always last)
    AddResult("search", "Search the web for  " q, "Google", q, gCatIcon["web"])

    ; select first row
    if (LV.GetCount())
        LV.Modify(1, "Select Focus")
}

AddResult(kind, title, sub, data, icon) {
    if (gResults.Length >= MAX_RESULTS)
        return
    gResults.Push(Map("kind", kind, "title", title, "sub", sub, "data", data))
    LV.Add("Icon" icon, title, sub)
}

; =====================================================================
;  Execution
; =====================================================================
ExecuteResult(res, admin := false) {
    kind := res["kind"], data := res["data"]
    switch kind {
        case "app":
            launch := data.Has("launch") ? data["launch"] : data["path"]
            if data.Has("uwp")
                Run(launch)                       ; shell:AppsFolder\<AppID>
            else if admin
                Run('*RunAs "' launch '"')
            else
                Run('"' launch '"')
        case "file", "folder", "url":
            Run(data)
        case "shell":
            Run(A_ComSpec ' /k ' data)
        case "search":
            Run("https://www.google.com/search?q=" UriEncode(data))
        case "calc":
            A_Clipboard := data
            TrayTip "CommandBar", "Copied: " data, 1
        case "os":
            data.Call()
    }
}

; =====================================================================
;  Application indexing
; =====================================================================
ScanApps() {
    global gApps, gIconCache
    gApps := []
    gIconCache := Map()
    seen := Map()
    dirs := [A_StartMenu, A_StartMenuCommon
           , A_Desktop, A_DesktopCommon
           , A_AppData "\Microsoft\Windows\Start Menu"]
    for d in dirs {
        if !DirExist(d)
            continue
        Loop Files, d "\*.*", "RF" {
            ext := StrLower(A_LoopFileExt)
            if (ext != "lnk" && ext != "url" && ext != "appref-ms")
                continue
            name := A_LoopFileName
            name := RegExReplace(name, "\.(lnk|url|appref-ms)$", "")
            key := StrLower(name)
            if seen.Has(key)
                continue
            seen[key] := true
            item := Map("name", name, "path", A_LoopFileFullPath, "launch", A_LoopFileFullPath)
            if (ext = "lnk") {
                try {
                    target := ""
                    FileGetShortcut(A_LoopFileFullPath, &target)
                    if (target != "")
                        item["target"] := target
                }
            }
            gApps.Push(item)
        }
    }

    ; --- UWP / Store apps + anything else in the shell "All apps" list ---
    ; shell:AppsFolder is exactly what Windows Search / Start "All apps" enumerate.
    try {
        appsFolder := ComObject("Shell.Application").Namespace("shell:AppsFolder")
        for it in appsFolder.Items() {
            name := it.Name
            key := StrLower(name)
            if (name = "" || seen.Has(key))
                continue
            seen[key] := true
            ; it.Path is the AppUserModelID; launchable via shell:AppsFolder\<id>
            gApps.Push(Map("name", name, "path", "Installed app"
                , "launch", "shell:AppsFolder\" it.Path, "uwp", true))
        }
    }

    TrayTip "CommandBar", "Indexed " gApps.Length " apps.", 1
}

; =====================================================================
;  OS operations & Settings shortcuts
; =====================================================================
OsCommands() {
    static cmds := ""
    if (cmds != "")
        return cmds
    cmds := [
        Cmd("Lock workstation",      "lock workstation screen",     "Win+L",        () => DllCall("LockWorkStation")),
        Cmd("Sleep",                 "sleep suspend standby",       "Power",        () => DllCall("PowrProf\SetSuspendState", "Int",0,"Int",0,"Int",0)),
        Cmd("Hibernate",             "hibernate",                   "Power",        () => DllCall("PowrProf\SetSuspendState", "Int",1,"Int",0,"Int",0)),
        Cmd("Shut down",             "shutdown power off turn off", "System",       () => Shutdown(8|4)),
        Cmd("Restart",               "restart reboot",              "System",       () => Shutdown(2|4)),
        Cmd("Sign out",              "sign out log off logout",     "Session",      () => Shutdown(0|4)),
        Cmd("Empty Recycle Bin",     "empty recycle bin trash",     "Files",        () => (DllCall("Shell32\SHEmptyRecycleBinW","Ptr",0,"Ptr",0,"UInt",7), TrayTip("CommandBar","Recycle Bin emptied",1))),
        Cmd("Lock screen (sleep monitor)", "monitor off screen off", "Display",     () => SendMessage(0x112, 0xF170, 2, , "Program Manager")),
        Cmd("Mute / Unmute",         "mute volume audio sound",     "Audio",        () => Send("{Volume_Mute}")),
        Cmd("Volume up",             "volume up louder",            "Audio",        () => Send("{Volume_Up 5}")),
        Cmd("Volume down",           "volume down quieter",         "Audio",        () => Send("{Volume_Down 5}")),
        Cmd("Task Manager",          "task manager processes",      "Tools",        () => Run("taskmgr.exe")),
        Cmd("Control Panel",         "control panel",               "Tools",        () => Run("control.exe")),
        Cmd("Device Manager",        "device manager hardware",     "Tools",        () => Run("devmgmt.msc")),
        Cmd("Registry Editor",       "registry editor regedit",     "Tools",        () => Run("regedit.exe")),
        Cmd("Command Prompt",        "command prompt cmd terminal", "Tools",        () => Run(A_ComSpec)),
        Cmd("PowerShell",            "powershell terminal",         "Tools",        () => Run("powershell.exe")),
        Cmd("Snipping Tool",         "snip screenshot capture",     "Tools",        () => Send("#+s")),
        Cmd("Empty Clipboard",       "clear clipboard",             "Clipboard",    () => (A_Clipboard := "", TrayTip("CommandBar","Clipboard cleared",1))),
        Cmd("Recycle Bin (open)",    "open recycle bin",            "Files",        () => Run("explorer.exe shell:RecycleBinFolder")),
        Cmd("This PC",               "this pc computer drives",     "Files",        () => Run("explorer.exe shell:MyComputerFolder")),
        Cmd("Downloads folder",      "downloads folder",            "Files",        () => Run("explorer.exe " A_MyDocuments "\..\Downloads")),
        ; ---- Settings pages (ms-settings:) ----
        Setting("Settings (home)",   "settings",                    ""),
        Setting("Wi-Fi settings",    "wifi wireless network",       "network-wifi"),
        Setting("Bluetooth settings","bluetooth devices",           "bluetooth"),
        Setting("Display settings",  "display screen resolution",   "display"),
        Setting("Sound settings",    "sound audio output",          "sound"),
        Setting("Apps & features",   "apps features uninstall programs", "appsfeatures"),
        Setting("Power & battery",   "power battery sleep plan",     "powersleep"),
        Setting("Windows Update",    "update windows update",        "windowsupdate"),
        Setting("Personalization",   "background theme wallpaper personalization", "personalization"),
        Setting("Default apps",      "default apps",                "defaultapps")
    ]
    return cmds
}

Cmd(title, keys, sub, fn) {
    return Map("title", title, "keys", keys, "sub", sub, "run", fn)
}
Setting(title, keys, page) {
    uri := "ms-settings:" page
    return Map("title", title, "keys", keys, "sub", "Open Windows Settings", "run", () => Run(uri))
}

; =====================================================================
;  Matching helpers
; =====================================================================
KeywordMatch(keys, q) {
    q := StrLower(q)
    for word in StrSplit(q, " ") {
        if (word = "")
            continue
        if !InStr(StrLower(keys), word)
            return false
    }
    return true
}

Score(name, q) {
    n := StrLower(name), q := StrLower(q)
    if (n = q)
        return 1000
    p := InStr(n, q)
    if (p = 1)
        return 900 - StrLen(name)
    if (p > 1) {
        before := SubStr(n, p-1, 1)
        if (before = " " || before = "-" || before = "_")
            return 700 - StrLen(name)
        return 500 - StrLen(name)
    }
    if Subsequence(n, q)
        return 300 - StrLen(name)
    return -1
}

Subsequence(hay, needle) {
    i := 1
    Loop Parse, needle {
        i := InStr(hay, A_LoopField, , i)
        if !i
            return false
        i++
    }
    return true
}

SortByScore(arr) {
    ; simple insertion sort, descending by .s
    Loop arr.Length {
        i := A_Index
        key := arr[i]
        j := i - 1
        while (j >= 1 && arr[j].s < key.s) {
            arr[j+1] := arr[j]
            j--
        }
        arr[j+1] := key
    }
}

; =====================================================================
;  URL / web helpers
; =====================================================================
IsUrl(s) {
    if RegExMatch(s, "i)^(https?|ftp)://")
        return true
    ; bare domain like example.com/path  (no spaces, has a dot, looks domainy)
    if (!InStr(s, " ") && RegExMatch(s, "i)^[\w-]+(\.[\w-]+)+(/.*)?$"))
        return true
    return false
}
NormalizeUrl(s) {
    return RegExMatch(s, "i)^[a-z]+://") ? s : "https://" s
}
UriEncode(str) {
    out := ""
    for ch in StrSplit(str) {
        if RegExMatch(ch, "[0-9A-Za-z\-_.~]")
            out .= ch
        else {
            ; encode each UTF-8 byte
            buf := Buffer(8, 0)
            n := StrPut(ch, buf, "UTF-8") - 1
            Loop n
                out .= Format("%{:02X}", NumGet(buf, A_Index-1, "UChar"))
        }
    }
    return out
}

; =====================================================================
;  Inline calculator  (shunting-yard, safe — no eval)
; =====================================================================
TryCalc(expr) {
    ; only attempt if it looks like math and contains an operator or paren
    if !RegExMatch(expr, "^[\s\d.+\-*/%^()]+$")
        return ""
    if !RegExMatch(expr, "[-+*/%^()]")
        return ""
    try {
        v := EvalMath(expr)
        if (v = "")
            return ""
        ; tidy float output
        if (v = Round(v))
            return Format("{}", Integer(Round(v)))
        return RegExReplace(Format("{:.10f}", v), "0+$", "")
    }
    return ""
}

EvalMath(expr) {
    tokens := Tokenize(expr)
    rpn := ToRPN(tokens)
    return EvalRPN(rpn)
}

Tokenize(s) {
    toks := [], i := 1, n := StrLen(s), prev := ""
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = " ") {
            i++
            continue
        }
        if RegExMatch(SubStr(s, i), "^\d+\.?\d*|^\.\d+", &m) {
            toks.Push({t:"num", v:m[0]+0})
            prev := "num"
            i += StrLen(m[0])
            continue
        }
        if InStr("+-*/%^", c) {
            ; unary minus/plus
            if ((c = "-" || c = "+") && (prev = "" || prev = "op" || prev = "(")) {
                toks.Push({t:"num", v:0})
                toks.Push({t:"op", v:c})
            } else {
                toks.Push({t:"op", v:c})
            }
            prev := "op"
            i++
            continue
        }
        if (c = "(") {
            toks.Push({t:"(", v:c}), prev := "(", i++
            continue
        }
        if (c = ")") {
            toks.Push({t:")", v:c}), prev := "num", i++
            continue
        }
        throw Error("bad char")
    }
    return toks
}

Prec(op) {
    if (op = "+" || op = "-")
        return 1
    if (op = "*" || op = "/" || op = "%")
        return 2
    if (op = "^")
        return 3
    return 0
}

ToRPN(toks) {
    out := [], ops := []
    for tk in toks {
        if (tk.t = "num")
            out.Push(tk)
        else if (tk.t = "op") {
            while (ops.Length) {
                top := ops[ops.Length]
                if (top.t = "op" && (Prec(top.v) > Prec(tk.v)
                        || (Prec(top.v) = Prec(tk.v) && tk.v != "^")))
                    out.Push(ops.Pop())
                else
                    break
            }
            ops.Push(tk)
        }
        else if (tk.t = "(")
            ops.Push(tk)
        else if (tk.t = ")") {
            while (ops.Length && ops[ops.Length].t != "(")
                out.Push(ops.Pop())
            if !ops.Length
                throw Error("paren")
            ops.Pop()
        }
    }
    while (ops.Length) {
        if (ops[ops.Length].t = "(")
            throw Error("paren")
        out.Push(ops.Pop())
    }
    return out
}

EvalRPN(rpn) {
    st := []
    for tk in rpn {
        if (tk.t = "num")
            st.Push(tk.v)
        else {
            if (st.Length < 2)
                throw Error("arity")
            b := st.Pop(), a := st.Pop()
            switch tk.v {
                case "+": st.Push(a + b)
                case "-": st.Push(a - b)
                case "*": st.Push(a * b)
                case "/": st.Push(a / b)
                case "%": st.Push(Mod(a, b))
                case "^": st.Push(a ** b)
            }
        }
    }
    if (st.Length != 1)
        throw Error("eval")
    return st[1]
}

; =====================================================================
;  Icons  (use the Windows system image list — looks native, zero deps)
; =====================================================================
AttachSystemImageList(hLV) {
    buf := Buffer(8 + 4 + 4 + 520 + 160, 0)
    ; SHGFI_SYSICONINDEX (0x4000) | SHGFI_SMALLICON (0x1)
    hIL := DllCall("Shell32\SHGetFileInfoW", "Str", "C:\", "UInt", 0
        , "Ptr", buf, "UInt", buf.Size, "UInt", 0x4000 | 0x1, "Ptr")
    if hIL
        SendMessage(0x1003, 1, hIL, hLV)   ; LVM_SETIMAGELIST, LVSIL_SMALL
}

; icon index for a real file/exe (cached)
GetIcon(path) {
    if gIconCache.Has(path)
        return gIconCache[path]
    idx := SysIconIndex(path, 0, 0)
    gIconCache[path] := idx
    return idx
}

; icon index using only a file attribute / extension (no disk hit)
SysIconIndex(name, attr, flagAttr) {
    static SIZE := 8 + 4 + 4 + 520 + 160
    buf := Buffer(SIZE, 0)
    flags := 0x4000 | 0x1                  ; SYSICONINDEX | SMALLICON
    if flagAttr
        flags |= 0x10                      ; USE_FILE_ATTRIBUTES
    DllCall("Shell32\SHGetFileInfoW", "Str", name, "UInt", attr
        , "Ptr", buf, "UInt", SIZE, "UInt", flags, "Ptr")
    return NumGet(buf, 8, "Int")
}

PrecacheCategoryIcons() {
    gCatIcon["folder"] := SysIconIndex("x",     0x10, 1)   ; FILE_ATTRIBUTE_DIRECTORY
    gCatIcon["web"]    := SysIconIndex("x.html", 0x80, 1)
    gCatIcon["calc"]   := SysIconIndex("x.txt",  0x80, 1)
    gCatIcon["shell"]  := SysIconIndex("x.bat",  0x80, 1)
    gCatIcon["os"]     := SysIconIndex("x.exe",  0x80, 1)
    gCatIcon["app"]    := SysIconIndex("x.exe",  0x80, 1)   ; generic icon for UWP apps
}
