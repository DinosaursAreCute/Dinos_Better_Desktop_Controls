#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  CUSTOM ACTIONS — add/remove entries here as needed
;  Format: "Display Name" => Func("FunctionName")
;          or use a lambda directly
; ============================================================
global customActions := Map(
    "Shutdown",         () => Shutdown(1),
    "Reboot",           () => Shutdown(2),
    "Sleep",            () => Shutdown(8),
    "Hibernate",        () => Shutdown(32),
    "Lock Screen",      () => DllCall("LockWorkStation"),
    "Sign Out",         () => Shutdown(0),
    "Open Workspaces",  Action_OpenWorkspaces,
    "Reload Launcher",  () => Reload(),
    "Exit Launcher",    () => ExitApp(),
    "Open Downloads",   Action_OpenDownloads,
    "Open Documents",   Action_OpenDocuments,
    "Open Scripts",     Action_OpenScripts,
    "Task Manager",     () => Run("taskmgr.exe"),
    "Control Panel",    () => Run("control.exe"),
)

Action_OpenWorkspaces(*) {
    Run(A_ScriptDir "\workspaces.ahk")
}
Action_OpenDownloads(*) {
    path := EnvGet("USERPROFILE") "\Downloads"
    Run("explorer `"" path "`"")
}
Action_OpenDocuments(*) {
    path := EnvGet("USERPROFILE") "\Documents"
    Run("explorer `"" path "`"")
}
Action_OpenScripts(*) {
    path := A_ScriptDir
    Run("explorer `"" path "`"")
}

; ============================================================
;  App scan — Start Menu .lnk locations
; ============================================================
global appList := []

ScanApps() {
    global appList
    appList := []
    dirs := [
        A_AppData "\Microsoft\Windows\Start Menu\Programs",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
    ]
    for dir in dirs {
        loop files dir "\*.lnk", "R" {
            name := RegExReplace(A_LoopFileName, "\.lnk$", "")
            appList.Push({ name: name, path: A_LoopFileFullPath })
        }
    }
}

ScanApps()

; ============================================================
;  Launcher state
; ============================================================
global launcherGui   := 0
global resultItems   := []   ; array of {name, action}  currently shown
global selectedIndex := 1

; ============================================================
;  Hotkey
; ============================================================
#Space:: ShowLauncher()

ShowLauncher() {
    global launcherGui, selectedIndex, resultItems

    if IsObject(launcherGui) {
        launcherGui.Destroy()
        launcherGui := 0
        return
    }

    selectedIndex := 1
    resultItems   := []

    W := 520
    screenW := A_ScreenWidth
    screenH := A_ScreenHeight
    xPos := (screenW - W) // 2
    yPos := (screenH // 2) - 160

    g := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "Launcher")
    g.BackColor := "0D0D0D"
    g.SetFont("s13 w400 cE0E0E0", "Segoe UI")
    g.OnEvent("Close", (*) => CloseLauncher())

    ; Search input
    g.SetFont("s14 w400 cFFFFFF", "Segoe UI")
    input := g.Add("Edit", "x12 y12 w496 h32 Background1A1A1A -E0x200 vSearchBox")
    input.OnEvent("Change", OnSearchChange)

    ; Results list (read-only, no edit)
    g.SetFont("s12 w400 cE0E0E0", "Segoe UI")
    resultBox := g.Add("ListBox", "x12 y52 w496 h400 Background141414 -E0x200 vResultBox")
    resultBox.OnEvent("DoubleClick", (*) => ExecuteSelected())

    g.Show("x" xPos " y" yPos " w520 NoActivate")

    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd,
        "UInt", 33, "Int*", 12, "UInt", 4)

    launcherGui := g

    ; Key bindings on the Edit control
    HotIfWinActive("Launcher ahk_class AutoHotkeyGUI")
    Hotkey("Escape",   (*) => CloseLauncher(),    "On")
    Hotkey("Enter",    (*) => ExecuteSelected(),  "On")
    Hotkey("Up",       (*) => MoveSelection(-1),  "On")
    Hotkey("Down",     (*) => MoveSelection(1),   "On")
    HotIfWinActive()

    ; Focus input
    input.Focus()
    PopulateResults("")
}

CloseLauncher() {
    global launcherGui
    if IsObject(launcherGui) {
        launcherGui.Destroy()
        launcherGui := 0
    }
}

; ============================================================
;  Search / filter
; ============================================================
OnSearchChange(ctrl, *) {
    PopulateResults(ctrl.Value)
}

PopulateResults(query) {
    global launcherGui, resultItems, selectedIndex, customActions, appList

    if !IsObject(launcherGui)
        return

    resultItems := []
    query := Trim(query)
    lq := StrLower(query)

    ; --- Calculator ---
    calcResult := TryCalc(query)
    if calcResult != ""
        resultItems.Push({ name: "= " calcResult, action: () => CalcCopy(calcResult) })

    ; --- Custom actions first ---
    for name, fn in customActions {
        if (lq = "" || InStr(StrLower(name), lq))
            resultItems.Push({ name: "[Action]  " name, action: fn })
    }

    ; --- Apps ---
    for app in appList {
        if (lq = "" || InStr(StrLower(app.name), lq))
            resultItems.Push({ name: app.name, action: () => RunApp(app.path) })
    }

    ; Rebuild ListBox
    lb := launcherGui["ResultBox"]
    lb.Delete()
    displayNames := []
    for item in resultItems
        displayNames.Push(item.name)
    if displayNames.Length > 0
        lb.Add(displayNames)

    selectedIndex := 1
    if resultItems.Length > 0
        lb.Choose(1)
}

; ============================================================
;  Calculator
; ============================================================
TryCalc(expr) {
    if !RegExMatch(expr, "^[\d\s\.\+\-\*\/\^\(\)]+$")
        return ""
    if !RegExMatch(expr, "[\d]")
        return ""
    try {
        result := Eval(expr)
        return (result == Floor(result)) ? Integer(result) : Round(result, 10)
    }
    return ""
}

CalcCopy(result) {
    A_Clipboard := result
    ToolTip("Copied: " result)
    SetTimer(() => ToolTip(), -1500)
}

Eval(expr) {
    expr := RegExReplace(expr, "\s", "")
    return EvalAddSub(expr, &pos := 1)
}

EvalAddSub(expr, &pos) {
    left := EvalMulDiv(expr, &pos)
    loop {
        if pos > StrLen(expr)
            break
        op := SubStr(expr, pos, 1)
        if op != "+" && op != "-"
            break
        pos++
        right := EvalMulDiv(expr, &pos)
        left := (op = "+") ? left + right : left - right
    }
    return left
}

EvalMulDiv(expr, &pos) {
    left := EvalPow(expr, &pos)
    loop {
        if pos > StrLen(expr)
            break
        op := SubStr(expr, pos, 1)
        if op != "*" && op != "/"
            break
        pos++
        right := EvalPow(expr, &pos)
        left := (op = "*") ? left * right : left / right
    }
    return left
}

EvalPow(expr, &pos) {
    base := EvalUnary(expr, &pos)
    if pos <= StrLen(expr) && SubStr(expr, pos, 1) = "^"
        pos++, base := base ** EvalPow(expr, &pos)
    return base
}

EvalUnary(expr, &pos) {
    if SubStr(expr, pos, 1) = "-" {
        pos++
        return -EvalAtom(expr, &pos)
    }
    return EvalAtom(expr, &pos)
}

EvalAtom(expr, &pos) {
    if SubStr(expr, pos, 1) = "(" {
        pos++
        val := EvalAddSub(expr, &pos)
        pos++
        return val
    }
    start := pos
    while pos <= StrLen(expr) && RegExMatch(SubStr(expr, pos, 1), "[\d\.]") {
        pos++
    }
    return Float(SubStr(expr, start, pos - start))
}

RunApp(path) {
    try Run(path)
    catch as e
        MsgBox "Could not launch:`n" path "`n`n" e.Message
}

; ============================================================
;  Navigation & execution
; ============================================================
MoveSelection(delta) {
    global launcherGui, selectedIndex, resultItems
    if !IsObject(launcherGui) || resultItems.Length = 0
        return
    selectedIndex := Max(1, Min(resultItems.Length, selectedIndex + delta))
    launcherGui["ResultBox"].Choose(selectedIndex)
}

ExecuteSelected() {
    global launcherGui, selectedIndex, resultItems
    if !IsObject(launcherGui) || resultItems.Length = 0
        return
    item := resultItems[selectedIndex]
    CloseLauncher()
    item.action()
}
