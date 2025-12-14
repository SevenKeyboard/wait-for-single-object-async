#Requires AutoHotkey v1.1.35+
;==============================================================
; WaitForSingleObjectAsync — Async wait helper for Win32 event handles
;
; GitHub: https://github.com/SevenKeyboard/wait-for-single-object-async
; Author: SevenKeyboard Ltd. (2025)
; License: See LICENSE (public-domain dedication for original code; third-party rights reserved).
;
; Original idea and low-level machine-code stub:
;   Script-Coding.ru ("Серый форум") — "AHK: Запуск скрипта не по кнопке, а при событии создания файла"
;     https://forum.script-coding.com/viewtopic.php?id=6231
;   Script-Coding.ru ("Серый форум") — "AHK: асинхронный вызов Wait-функции"
;     https://forum.script-coding.com/viewtopic.php?id=6739
;
; Documentation / References:
;   AutoHotkey forum — "(winapi) RegNotifyChangeKeyValue Access is denied."
;     https://www.autohotkey.com/boards/viewtopic.php?p=475934#p475979
;   AutoHotkey forum — "Detect file change"
;     https://www.autohotkey.com/boards/viewtopic.php?t=76244#p330441
;==============================================================
class VersionManager_WaitForSingleObjectAsync
{
    static _ := VersionManager_WaitForSingleObjectAsync._init()
    _init()    {
        global
        WAITFORSINGLEOBJECTASYNC_VERSION := "1.0.0"
    }
}
class WaitForSingleObjectAsync
{
    __new(hEvent, userFunc)    {
        this.EventSignal := new this._EventSignal(hEvent, userFunc)
    }

    __delete()    {
        this.EventSignal.clear()
    }

    class _EventSignal
    {
        __new(hEvent, userFunc)    {
            this.WM_EVENTSIGNAL := dllCall("User32.dll\RegisterWindowMessage", "Str","WM_EVENTSIGNAL")
            this.hEvent     := hEvent
            this.userFunc   := userFunc
            this.onEvent    := objBindMethod(this, "_onEventSignal")
            onMessage(this.WM_EVENTSIGNAL, this.onEvent)
            this.startAddress := this._createWaitFunc(this.hEvent, A_ScriptHwnd, this.WM_EVENTSIGNAL)
            this.Thread := new this._Thread(this.startAddress)
        }
        
        _onEventSignal(wParam, _*)    { ;  WM_EVENTSIGNAL
            if (wParam !== this.hEvent)
                return
            timer := this.userFunc
            setTimer % timer, -10
            this.Thread.wait()
            this.Thread := new this._Thread(this.startAddress)
        }

        _createWaitFunc(hEvent, hWnd, msg, timeout := -1)    {
            params := ["UInt",MEM_COMMIT := 0x1000, "UInt",PAGE_EXECUTE_READWRITE := 0x40, "Ptr"]
            ptr := dllCall("Kernel32.dll\VirtualAlloc", "Ptr",0, "Ptr",A_PtrSize == 4 ? 49 : 85, params*)
            hModule      := dllCall("Kernel32.dll\GetModuleHandle", "Str","Kernel32.dll", "Ptr")
            pWaitForObj  := dllCall("Kernel32.dll\GetProcAddress" , "Ptr",hModule, "AStr","WaitForSingleObject", "Ptr")
            hModule      := dllCall("Kernel32.dll\GetModuleHandle", "Str","User32.dll", "Ptr")
            pPostMessage := dllCall("Kernel32.dll\GetProcAddress" , "Ptr",hModule, "AStr","PostMessageW", "Ptr")
            numPut(pWaitForObj , ptr + 0)
            numPut(pPostMessage, ptr + A_PtrSize)
            if (A_PtrSize == 4)    {
                numPut(0x68   , ptr +  8)
                numPut(timeout, ptr +  9)           , numPut(0x68  , ptr + 13)
                numPut(hEvent , ptr + 14)           , numPut(0x15FF, ptr + 18)
                numPut(ptr    , ptr + 20)           , numPut(0x6850, ptr + 24)
                numPut(hEvent , ptr + 26)           , numPut(0x68  , ptr + 30)
                numPut(msg    , ptr + 31)           , numPut(0x68  , ptr + 35)
                numPut(hWnd   , ptr + 36)           , numPut(0x15FF, ptr + 40)
                numPut(ptr + 4, ptr + 42)           , numPut(0xC2  , ptr + 46, "UChar")
                numPut(4      , ptr + 47, "UShort")
            }  else  {
                numPut(0x53      , ptr + 16)
                numPut(0x20EC8348, ptr + 17)        , numPut(0xBACB8948, ptr + 21)
                numPut(timeout   , ptr + 25)        , numPut(0xB948    , ptr + 29)
                numPut(hEvent    , ptr + 31)        , numPut(0x15FF    , ptr + 39)
                numPut(-45       , ptr + 41)        , numPut(0xB849    , ptr + 45)
                numPut(hEvent    , ptr + 47)        , numPut(0xBA      , ptr + 55)
                numPut(msg       , ptr + 56)        , numPut(0xB948    , ptr + 60)
                numPut(hWnd      , ptr + 62)        , numPut(0xC18941  , ptr + 70)
                numPut(0x15FF    , ptr + 73)        , numPut(-71       , ptr + 75)
                numPut(0x20C48348, ptr + 79, "UInt"), numPut(0xC35B    , ptr + 83, "UShort")
            }
            return ptr + A_PtrSize * 2
        }
        
        class _Thread
        {
            __new(startAddress)    {
                if !this.handle := dllCall("Kernel32.dll\CreateThread", "Int", 0, "Int", 0, "Ptr", startAddress, "Int", 0, "UInt", 0, "Int", 0, "Ptr")
                    throw Exception("Failed to create thread.`nError code: " . A_LastError)
            }
            wait()    {
                dllCall("Kernel32.dll\WaitForSingleObject", "Ptr",this.handle, "Int",-1)
            }
            __delete()    {
                dllCall("Kernel32.dll\CloseHandle", "Ptr",this.handle)
            }
        }
        
        clear()    {
            this.Thread.wait()
            onMessage(this.WM_EVENTSIGNAL, this.onEvent, 0)
            this.onEvent := ""
            dllCall("Kernel32.dll\VirtualFree", "Ptr",this.startAddress - A_PtrSize * 2, "Ptr",A_PtrSize == 4 ? 49 : 85, "UInt",MEM_DECOMMIT := 0x4000)
        }
    }
}