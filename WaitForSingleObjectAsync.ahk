#Requires AutoHotkey v2.0.0+
;==============================================================
; WaitForSingleObjectAsync — Async wait helper for Win32 event handles
;
; GitHub: https://github.com/SevenKeyboard/wait-for-single-object-async
; Author: SevenKeyboard Ltd. (2025)
; License: The Unlicense
;
; Original idea and low-level machine-code stub:
;   Script-Coding.ru ("gray forum") — "Запуск скрипта не по кнопке, а при событии создания файла"
;     https://forum.script-coding.com/viewtopic.php?id=6231
;   Script-Coding.ru ("gray forum") — "AHK: асинхронный вызов Wait-функции"
;     https://forum.script-coding.com/viewtopic.php?id=6739
;   Script-Coding.ru ("gray forum") — related original post
;     http://forum.script-coding.com/viewtopic.php?pid=56073#p56073
;
; Documentation / References:
;   AutoHotkey forum — "(winapi) RegNotifyChangeKeyValue Access is denied."
;     https://www.autohotkey.com/boards/viewtopic.php?p=475934#p475979
;   AutoHotkey forum — "Detect file change"
;     https://www.autohotkey.com/boards/viewtopic.php?t=76244#p330441
;==============================================================
class VersionManager_WaitForSingleObjectAsync
{
    static _ := this._init()
    static _init()    {
        global
        WAITFORSINGLEOBJECTASYNC_VERSION := "1.0.0"
    }
}
class WaitForSingleObjectAsync
{
    __new(hEvent, userFunc)    {
        this.EventSignal := WaitForSingleObjectAsync._EventSignal(hEvent, userFunc)
    }

    __delete()    {
        this.EventSignal.clear()
    }

    class _EventSignal
    {
        __new(hEvent, userFunc)    {
            this.WM_EVENTSIGNAL := dllCall("RegisterWindowMessage", "Str","WM_EVENTSIGNAL")
            this.hEvent     := hEvent
            this.userFunc   := userFunc
            this.onEvent    := objBindMethod(this, "onEventSignal")
            onMessage(this.WM_EVENTSIGNAL, this.onEvent)
            this.startAddress := this.createWaitFunc(this.hEvent, A_ScriptHwnd, this.WM_EVENTSIGNAL)
            this.Thread := WaitForSingleObjectAsync._EventSignal._Thread(this.startAddress)
        }
        
        onEventSignal(wp)    { ;  WM_EVENTSIGNAL
            if (wp !== this.hEvent)
                return

            setTimer(this.userFunc, -10)

            this.Thread.wait()
            this.Thread := WaitForSingleObjectAsync._EventSignal._Thread(this.startAddress)
        }

        createWaitFunc(hEvent, hWnd, msg, timeout := -1)    {
            params := ["UInt",MEM_COMMIT := 0x1000, "UInt",PAGE_EXECUTE_READWRITE := 0x40, "Ptr"]
            ptr := dllCall("VirtualAlloc", "Ptr",0, "Ptr",A_PtrSize == 4 ? 49 : 85, params*)
            hModule      := dllCall("GetModuleHandle", "Str","Kernel32.dll", "Ptr")
            pWaitForObj  := dllCall("GetProcAddress" , "Ptr",hModule, "AStr","WaitForSingleObject", "Ptr")
            hModule      := dllCall("GetModuleHandle", "Str","User32.dll", "Ptr")
            pPostMessage := dllCall("GetProcAddress" , "Ptr",hModule, "AStr","PostMessageW", "Ptr")
            numPut("UPtr", pWaitForObj , ptr + 0)
            numPut("UPtr", pPostMessage, ptr + A_PtrSize)
            if (A_PtrSize == 4)    {
                numPut("UPtr"  , 0x68   , ptr +  8)
                numPut("UPtr"  , timeout, ptr +  9)         , numPut("UPtr" , 0x68  , ptr + 13)
                numPut("UPtr"  , hEvent , ptr + 14)         , numPut("UPtr" , 0x15FF, ptr + 18)
                numPut("UPtr"  , ptr    , ptr + 20)         , numPut("UPtr" , 0x6850, ptr + 24)
                numPut("UPtr"  , hEvent , ptr + 26)         , numPut("UPtr" , 0x68  , ptr + 30)
                numPut("UPtr"  , msg    , ptr + 31)         , numPut("UPtr" , 0x68  , ptr + 35)
                numPut("UPtr"  , hWnd   , ptr + 36)         , numPut("UPtr" , 0x15FF, ptr + 40)
                numPut("UPtr"  , ptr + 4, ptr + 42)         , numPut("UChar", 0xC2  , ptr + 46)
                numPut("UShort", 4      , ptr + 47)
            }  else  {
                numPut("UPtr", 0x53      , ptr + 16)
                numPut("UPtr", 0x20EC8348, ptr + 17)        , numPut("UPtr"  , 0xBACB8948, ptr + 21)
                numPut("UPtr", timeout   , ptr + 25)        , numPut("UPtr"  , 0xB948    , ptr + 29)
                numPut("UPtr", hEvent    , ptr + 31)        , numPut("UPtr"  , 0x15FF    , ptr + 39)
                numPut("UPtr", -45       , ptr + 41)        , numPut("UPtr"  , 0xB849    , ptr + 45)
                numPut("UPtr", hEvent    , ptr + 47)        , numPut("UPtr"  , 0xBA      , ptr + 55)
                numPut("UPtr", msg       , ptr + 56)        , numPut("UPtr"  , 0xB948    , ptr + 60)
                numPut("UPtr", hWnd      , ptr + 62)        , numPut("UPtr"  , 0xC18941  , ptr + 70)
                numPut("UPtr", 0x15FF    , ptr + 73)        , numPut("UPtr"  , -71       , ptr + 75)
                numPut("UInt", 0x20C48348, ptr + 79)        , numPut("UShort", 0xC35B    , ptr + 83)
            }
            return ptr + A_PtrSize * 2
        }
        
        class _Thread
        {
            __new(startAddress)    {
                if !this.handle := dllCall("CreateThread", "Int", 0, "Int", 0, "Ptr", startAddress, "Int", 0, "UInt", 0, "Int", 0, "Ptr")
                    throw error("Failed to create thread.`nError code: " . A_LastError)
            }
            wait()    {
                dllCall("WaitForSingleObject", "Ptr",this.handle, "Int",-1)
            }
            __delete()    {
                dllCall("CloseHandle", "Ptr",this.handle)
            }
        }
        
        clear()    {
            this.Thread.wait()
            onMessage(this.WM_EVENTSIGNAL, this.onEvent, 0)
            this.onEvent := ""
            dllCall("VirtualFree", "Ptr",this.startAddress - A_PtrSize * 2, "Ptr",A_PtrSize == 4 ? 49 : 85, "UInt",MEM_DECOMMIT := 0x4000)
        }
    }
}