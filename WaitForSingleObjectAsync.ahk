#Requires AutoHotkey v2.0.0+
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
    static _ := this._init()
    static _init()    {
        global
        WAITFORSINGLEOBJECTASYNC_VERSION := "1.1.0"
    }
}
class WaitForSingleObjectAsync
{
    __new(hEvent, userFunc)    {
        this.EventSignal := ""
        this.EventSignal := WaitForSingleObjectAsync._EventSignal(hEvent, userFunc)
    }

    __delete()    {
        if (isObject(this.EventSignal))
            this.EventSignal._dispose()
        this.EventSignal := ""
    }

    class _EventSignal
    {
        __new(hEvent, userFunc)    {
            this._disposed := false
            this.WM_EVENTSIGNAL := dllCall("User32.dll\RegisterWindowMessage", "Str","WM_EVENTSIGNAL")
            this.hEvent       := hEvent
            this.userFunc     := userFunc
            this.hCancelEvent := 0
            this.onEvent       := ""
            this.timerCallback := ""
            this._isMessageMonitorRegistered := false
            this.startAddress := 0
            this.Thread := ""
            this.hCancelEvent := dllCall("Kernel32.dll\CreateEvent", "Ptr",0, "Int",false, "Int",false, "Ptr",0, "Ptr")
            if (!this.hCancelEvent)
                throw error("Failed to create cancellation event.`nError code: " . A_LastError)
            try    {
                this.onEvent       := objBindMethod(this, "_onEventSignal")
                this.timerCallback := objBindMethod(this, "_callUserFunc")
                onMessage(this.WM_EVENTSIGNAL, this.onEvent)
                this._isMessageMonitorRegistered := true
                this.startAddress := this._createWaitFunc(this.hEvent, this.hCancelEvent, A_ScriptHwnd, this.WM_EVENTSIGNAL)
                this.Thread := WaitForSingleObjectAsync._EventSignal._Thread(this.startAddress)
            }  catch as e  {
                this._dispose()
                throw e
            }
        }
        
        _onEventSignal(wParam, waitResult, *)    { ;  WM_EVENTSIGNAL
            static WAIT_OBJECT_0 := 0
            if (wParam !== this.hEvent)
                return
            prevCritical := A_IsCritical
            critical("On")
            try    {
                if (this._disposed || waitResult !== WAIT_OBJECT_0)
                    return
                setTimer(this.timerCallback, -10)
                this.Thread.wait()
                this.Thread := ""
                this.Thread := WaitForSingleObjectAsync._EventSignal._Thread(this.startAddress)
            }  finally  {
                critical(prevCritical)
            }
        }

        _callUserFunc()    {
            if (this._disposed)
                return
            return this.userFunc.call()
        }

        _createWaitFunc(hEvent, hCancelEvent, hWnd, msg, timeout := -1)    {
            /*
            Native worker equivalent:
                handles[0] := hEvent
                handles[1] := hCancelEvent
                waitResult := WaitForMultipleObjects(2, &handles, false, timeout)
                PostMessageW(hWnd, msg, hEvent, waitResult)

            Memory layout before the executable code:
                0 * A_PtrSize: WaitForMultipleObjects address
                1 * A_PtrSize: PostMessageW address
                2 * A_PtrSize: hEvent
                3 * A_PtrSize: hCancelEvent
            */
            allocationSize := A_PtrSize == 4 ? 67 : 105
            params := ["UInt",MEM_COMMIT := 0x1000, "UInt",PAGE_EXECUTE_READWRITE := 0x40, "Ptr"]
            ptr := dllCall("Kernel32.dll\VirtualAlloc", "Ptr",0, "Ptr",allocationSize, params*)
            hModule         := dllCall("Kernel32.dll\GetModuleHandle", "Str","Kernel32.dll", "Ptr")
            pWaitForObjects := dllCall("Kernel32.dll\GetProcAddress", "Ptr",hModule, "AStr","WaitForMultipleObjects", "Ptr")
            hModule         := dllCall("Kernel32.dll\GetModuleHandle", "Str","User32.dll", "Ptr")
            pPostMessage    := dllCall("Kernel32.dll\GetProcAddress" , "Ptr",hModule, "AStr","PostMessageW", "Ptr")
            numPut("Ptr", pWaitForObjects, ptr + 0)
            numPut("Ptr", pPostMessage   , ptr + A_PtrSize)
            numPut("Ptr", hEvent         , ptr + A_PtrSize * 2)
            numPut("Ptr", hCancelEvent   , ptr + A_PtrSize * 3)
            if (A_PtrSize == 4)    {
                code := ptr + 16

                ;  WaitForMultipleObjects(2, ptr + 8, false, timeout)
                numPut("UChar" , 0x68   , code +  0)  , numPut("UInt", timeout, code +  1)
                numPut("UChar" , 0x68   , code +  5)  , numPut("UInt", 0      , code +  6)
                numPut("UChar" , 0x68   , code + 10)  , numPut("UInt", ptr + 8, code + 11)
                numPut("UChar" , 0x68   , code + 15)  , numPut("UInt", 2      , code + 16)
                numPut("UShort", 0x15FF , code + 20)  , numPut("UInt", ptr    , code + 22)

                ;  PostMessageW(hWnd, msg, hEvent, waitResult)
                numPut("UChar" , 0x50   , code + 26)
                numPut("UChar" , 0x68   , code + 27)  , numPut("UInt", hEvent , code + 28)
                numPut("UChar" , 0x68   , code + 32)  , numPut("UInt", msg    , code + 33)
                numPut("UChar" , 0x68   , code + 37)  , numPut("UInt", hWnd   , code + 38)
                numPut("UShort", 0x15FF , code + 42)  , numPut("UInt", ptr + 4, code + 44)

                ;  Return from the thread procedure.
                numPut("UChar", 0xC2, code + 48)      , numPut("UShort", 4, code + 49)
            }  else  {
                code := ptr + 32

                ;  Reserve stack space for Win64 calls.
                numPut("UInt", 0x28EC8348, code + 0)

                ;  WaitForMultipleObjects(2, ptr + 16, false, timeout)
                numPut("UShort", 0xB941, code +  4)  , numPut("UInt" , timeout , code +  6)
                numPut("UShort", 0x3145, code + 10)  , numPut("UChar", 0xC0    , code + 12)
                numPut("UShort", 0xBA48, code + 13)  , numPut("Ptr"  , ptr + 16, code + 15)
                numPut("UChar" , 0xB9  , code + 23)  , numPut("UInt" , 2       , code + 24)
                numPut("UShort", 0x15FF, code + 28)  , numPut("Int"  , -66     , code + 30)

                ;  PostMessageW(hWnd, msg, hEvent, waitResult)
                numPut("UShort", 0x8941, code + 34)  , numPut("UChar", 0xC1  , code + 36)
                numPut("UShort", 0xB849, code + 37)  , numPut("Ptr"  , hEvent, code + 39)
                numPut("UChar" , 0xBA  , code + 47)  , numPut("UInt" , msg   , code + 48)
                numPut("UShort", 0xB948, code + 52)  , numPut("Ptr"  , hWnd  , code + 54)
                numPut("UShort", 0x15FF, code + 62)  , numPut("Int"  , -92   , code + 64)

                ;  Restore the stack and return from the thread procedure.
                numPut("UInt", 0x28C48348, code + 68)  , numPut("UChar", 0xC3, code + 72)
            }
            return code
        }
        
        class _Thread
        {
            __new(startAddress)    {
                if !this.handle := dllCall("Kernel32.dll\CreateThread", "Int", 0, "Int", 0, "Ptr", startAddress, "Int", 0, "UInt", 0, "Int", 0, "Ptr")
                    throw error("Failed to create thread.`nError code: " . A_LastError)
            }
            wait()    {
                dllCall("Kernel32.dll\WaitForSingleObject", "Ptr",this.handle, "Int",-1)
            }
            __delete()    {
                dllCall("Kernel32.dll\CloseHandle", "Ptr",this.handle)
            }
        }
        
        _dispose()    {
            if (this._disposed)
                return
            prevCritical := A_IsCritical
            critical("On")
            try    {
                this._disposed := true
                if (isObject(this.timerCallback))
                    setTimer(this.timerCallback, 0)
                if (this._isMessageMonitorRegistered)    {
                    onMessage(this.WM_EVENTSIGNAL, this.onEvent, 0)
                    this._isMessageMonitorRegistered := false
                }
                if (this.hCancelEvent)
                    dllCall("Kernel32.dll\SetEvent", "Ptr",this.hCancelEvent)
                if (isObject(this.Thread))    {
                    this.Thread.wait()
                    this.Thread := ""
                }
                this.onEvent       := ""
                this.timerCallback := ""
                this.userFunc      := ""
                if (this.startAddress)    {
                    dllCall("Kernel32.dll\VirtualFree", "Ptr",this.startAddress - A_PtrSize * 4, "Ptr",0, "UInt",MEM_RELEASE := 0x8000)
                    this.startAddress := 0
                }
                if (this.hCancelEvent)    {
                    dllCall("Kernel32.dll\CloseHandle", "Ptr",this.hCancelEvent)
                    this.hCancelEvent := 0
                }
            }  finally  {
                critical(prevCritical)
            }
        }
    }
}
