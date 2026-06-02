#Requires AutoHotkey v2.0
#SingleInstance Force

hVDA := DllCall("LoadLibrary", "Str", A_ScriptDir "\VirtualDesktopAccessor.dll", "Ptr")
if !hVDA {
    MsgBox "VirtualDesktopAccessor.dll not found.`nLooked in: " A_ScriptDir "\VirtualDesktopAccessor.dll", "AutoKey Setup Error", "IconX"
    ExitApp
}

; --- Tray icon setup ---
A_TrayMenu.Delete()  ; remove default tray items

; Win+1 through Win+9: switch to workspace N
#1:: GoToDesktop(1)
#2:: GoToDesktop(2)
#3:: GoToDesktop(3)
#4:: GoToDesktop(4)
#5:: GoToDesktop(5)
#6:: GoToDesktop(6)
#7:: GoToDesktop(7)
#8:: GoToDesktop(8)
#9:: GoToDesktop(9)

; Win+Shift+1 through Win+Shift+9: move active window to workspace N
#+1:: MoveToDesktop(1)
#+2:: MoveToDesktop(2)
#+3:: MoveToDesktop(3)
#+4:: MoveToDesktop(4)
#+5:: MoveToDesktop(5)
#+6:: MoveToDesktop(6)
#+7:: MoveToDesktop(7)
#+8:: MoveToDesktop(8)
#+9:: MoveToDesktop(9)

GoToDesktop(n) {
    DllCall("VirtualDesktopAccessor.dll\GoToDesktopNumber", "Int", n - 1, "Int")
    ShowToast(n)

}

MoveToDesktop(n) {
    hwnd := WinExist("A")
    DllCall("VirtualDesktopAccessor.dll\MoveWindowToDesktopNumber", "Ptr", hwnd, "Int", n - 1, "Int")
    DllCall("VirtualDesktopAccessor.dll\GoToDesktopNumber", "Int", n - 1, "Int")
    ShowToast(n, true)

}

; --- Toast popup (top-center, auto-hides after 1.2s) ---
ShowToast(n, moving := false) {
    static toastGui := 0
    static hideTimer := 0

    if toastGui {
        toastGui.Destroy()
    }

    label := moving ? "Moved to  " . n : "Desktop  " . n

    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Toast")
    g.BackColor := "1a1a2e"
    g.SetFont("s22 w700 c00d4ff", "Consolas")
    g.Add("Text", "x20 y14", label)

    ; position: top-center of primary monitor
    screenW := SysGet(78)   ; SM_CXVIRTUALSCREEN width of primary
    screenW := A_ScreenWidth
    g.Show("NoActivate x" (screenW // 2 - 130) " y40 w260 h58")

    ; rounded corners via DWM
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd,
        "UInt", 33, "Int*", 12, "UInt", 4)  ; DWMWA_WINDOW_CORNER_PREFERENCE = round

    toastGui := g

    SetTimer(() => (IsObject(toastGui) ? toastGui.Destroy() : 0, toastGui := 0), -1200)
}

