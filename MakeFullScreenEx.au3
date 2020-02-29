#NoTrayIcon
#include <Array.au3>
#include <WinAPI.au3>
#include <Constants.au3>
#include <AutoItConstants.au3>
#include <WindowsConstants.au3>
#include <MsgBoxConstants.au3>
#include <TrayConstants.au3>
#include <Process.au3>

Opt("TrayAutoPause", 0)
Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)

Dim $iPollTime = 250 ; Scan rate for detecting new windows.
Dim $iScreenWidth = 1920 ; Width in pixels of your main monitor
Dim $iScreenHeight = 1080 ; Height in pixels of your main monitor
Dim $iDebugMode = 0 ; 1 = Print matching windows and actions taken upon them(for logging purposes), 4 = print everything done by this program(for debugging purposes).
Dim $sDebugWindowTitle = "dream" ; Use this for debugging any potential issues with specific windows (need debug mode 3 or above)
Dim $sConfigFile = StringFormat("%s\MakeFullScreenEx\profiles.ini", @AppDataDir)

Dim $iTimer
Dim $iPersistentTimer = TimerInit() ; Check persistent windows at a different interval than the main loop.
; No need to mod anything below.
Dim $aPersistent[1][2] = [[0, 0]]
If Not FileExists($sConfigFile) Then
	DirCreate(StringLeft($sConfigFile, StringInStr($sConfigFile, "\", 0, -1))) ; Create directory for config file
Else
	$aPersistent = IniReadSection($sConfigFile, "Persistent")
;~ 	_ArrayDisplay($aPersistent)
EndIf

Dim $aMatchedWindows[1][2] = [[0, 0]]
Dim $hLastWindow = -1

Dim $hMatchingMenu = TrayCreateMenu("Make fullscreen ->")
Dim $hExit = TrayCreateItem("Exit")

TrayItemSetOnEvent($hExit, "_Exit")
TraySetClick(1)
TraySetOnEvent($TRAY_EVENT_SECONDARYUP, "_SetPersistent")
TraySetState($TRAY_ICONSTATE_SHOW)

Func _DbgPrint($svMsg)
	ConsoleWrite(StringFormat("[DEBUG]: %s\n", $svMsg))
EndFunc

Func _MakeWinFullscreenWindowed($hWnd)
	If $iDebugMode > 0 Then _DbgPrint(StringFormat("Making window '%s' [%X] full screen!", WinGetTitle($hWnd), $hWnd))

	Local $iWinStyle = _WinAPI_GetWindowLong($hWnd, $GWL_STYLE)
	Local $iNewWinStyle = BitAND($iWinStyle, BitNOT(BitOR($WS_CAPTION, $WS_THICKFRAME, $WS_MINIMIZE, $WS_MAXIMIZE, $WS_SYSMENU)))
	_WinAPI_SetWindowLong($hWnd, $GWL_STYLE, $iNewWinStyle)

	Local $iWinExStyle = _WinAPI_GetWindowLong($hWnd, $GWL_EXSTYLE)
	Local $iNewWinExStyle = BitAND($iWinExStyle, BitNOT(BitOR($WS_EX_CLIENTEDGE, $WS_EX_WINDOWEDGE)))
	_WinAPI_SetWindowLong($hWnd, $GWL_EXSTYLE, $iNewWinExStyle)

	WinMove($hWnd, "", 0, 0, $iScreenWidth, $iScreenHeight, 1)
EndFunc

Func _WindowHasStyle($hWnd, $iStyle, $iCriteria) ; Could probably make it work, but too drunk to solve.
	If BitOR($iStyle, $iCriteria) Then Return True
	Return False
EndFunc
Func _IsOnMainScreen($hWnd)
	Local $avCoordinates = WingetPos($hWnd)
	If @error Then Return(SetError(2, 0, False)) ; Other, invalid window
	Local $ivFudgeArea = 10 ; Allow this much give in the detection of main screen windows position
	If ($avCoordinates[0] < 0 And $avCoordinates[0] < -$ivFudgeArea) Or $avCoordinates[0]-$iScreenWidth > $ivFudgeArea Then
		Return(SetError(3, 0, False)) ; Window is not on main monitor (guesstimatically!)
	EndIf
	If $iDebugMode >= 3 Then _DbgPrint(StringFormat("Window '%s' [%X] is on main screen [X:%i Y:%i]", WinGetTitle($hWnd), $hWnd, $avCoordinates[0], $avCoordinates[1]))
	Return True
EndFunc
Func _IsWindowed($hWnd)
	Local $avCoordinates = WingetPos($hWnd)
	If @error Then Return(SetError(2, 0, False)) ; Other, invalid window
	Local $ivFudgeFactor = 0.0001 ; Factor of $iScreenWidth that needs to match for window to be determined to be windowed instead of fullscreen.
	If $avCoordinates[2]/$iScreenWidth >= $ivFudgeFactor And $avCoordinates[3]/$iScreenHeight >= $ivFudgeFactor Then Return True
	Return False
EndFunc


Func _CheckWindow($hWnd)
	If Not WinExists($hWnd) Then Return False
	Local $sWinTitle = WinGetTitle($hWnd)
	If StringLen($sWinTitle) < 1 Then Return(SetError(1, 0, False)) ; Skip windows with no title.
	If Not BitAND(WinGetState($hWnd), 2) Then Return False ; Not visible(aka. hidden - not minimized)
	If _IsOnMainScreen($hWnd) Then
		If Not _IsWindowed($hWnd) Then
			If $iDebugMode >= 3 Then _DbgPrint(StringFormat("\tWindow '%s' [%X] is Fullscreen.", $sWinTitle, $hWnd))
			Return False
		Else
			If $iDebugMode >= 3 Then _DbgPrint(StringFormat("\tWindow '%s' [%X] is !NOT! Fullscreen.", $sWinTitle, $hWnd))
			Return True
		EndIf
	EndIf
	If $iDebugMode >= 4 And StringInStr($sWinTitle, $sDebugWindowTitle) Then _DbgPrint(StringFormat("Window '%s' [%X] is !NOT! on main screen.", $sWinTitle, $hWnd))
	Return False
EndFunc

Func _DetectWindowedMode()
	Local $avRet = [0]
	Local $avAllWin = WinList()
	For $iv = 1 To $avAllWin[0][0]
		If Not BitAND(WinGetState($avAllWin[$iv][1]), $WIN_STATE_VISIBLE) Then ContinueLoop ; Skip windows that aren't visible.
		If $iDebugMode >= 4 And StringInStr($avAllWin[$iv][0], $sDebugWindowTitle) Then _DbgPrint(StringFormat("Checking window: '%s' [%s]", $avAllWin[$iv][0], _WinAPI_GetClassName($avAllWin[$iv][1])))
		If _CheckWindow($avAllWin[$iv][1]) Then
			$avRet[0] += 1
			ReDim $avRet[$avRet[0]+1]
			$avRet[$avRet[0]] = $avAllWin[$iv][1]
		EndIf
		Sleep(1)
	Next
	Return $avRet
EndFunc

Func _Exit()
	Exit
EndFunc

Func _MenuItemClicked()
	Local $hTrayItem = @TRAY_ID
	$hLastWindow = -1
	For $iv = 1 To $aMatchedWindows[0][0]
		If $aMatchedWindows[$iv][0] == $hTrayItem Then
			$hLastWindow = $aMatchedWindows[$iv][1]
			ExitLoop
		EndIf
		Sleep(1)
	Next
	If Not WinExists($hLastWindow) Then Return ; Failsafe in case a non-existant window is still in the array.
	If $iDebugMode > 0 Then _DbgPrint(StringFormat("Tray item %i pressed belonging to window %s [%X]\n", $hTrayItem, WinGetTitle($hLastWindow), $hLastWindow))
	_MakeWinFullscreenWindowed($hLastWindow) ; Finally make the magic happen!
	TrayTip("Note!", StringFormat('Rightclick the tray icon to automate fullscreen setting of "%s"!', WinGetTitle($hLastWindow)), 3)
EndFunc

Func _SetPersistent()
	If $hLastWindow == -1 Or Not WinExists($hLastWindow) Then Return False
	Local $ivChoice = MsgBox(4, "Save setting", StringFormat('Do you want to save setting for "%s" so it will automatically be applied next time?', WinGetTitle($hLastWindow)))
	If $ivChoice <> 6 Then Return False
	Local $svProcessName = _ProcessGetName(WinGetProcess($hLastWindow))
	Local $ivWindowStyle = _WinAPI_GetWindowLong($hLastWindow, $GWL_STYLE)
	Local $ivWindowStyleEx = _WinAPI_GetWindowLong($hLastWindow, $GWL_EXSTYLE)
;~ 	IniWrite($sConfigFile, "Persistent", $svProcessName, StringFormat("%i,%i", $ivWindowStyle, $ivWindowStyleEx))
	$aPersistent[0][0] += 1
	ReDim $aPersistent[$aPersistent[0][0]+1][2]
	$aPersistent[$aPersistent[0][0]][0] = $svProcessName
	$aPersistent[$aPersistent[0][0]][1] = StringFormat("%i,%i", $ivWindowStyle, $ivWindowStyleEx)
	IniWriteSection($sConfigFile, "Persistent", $aPersistent)
	TrayTip("Note!", StringFormat("Saved settings to %s", $sConfigFile), 1)
EndFunc

Func _TestPersistent($hWnd)
	If Not WinExists($hWnd) Then Return False
	For $iv = 1 To $aPersistent[0][0]
		If $aPersistent[$iv][0] == _ProcessGetName(WinGetProcess($hWnd)) Then
			Local $avStyles = StringSplit($aPersistent[$iv][1], ",", 2)
			Local $avCurrentStyles[2] = [_WinAPI_GetWindowLong($hWnd, $GWL_STYLE), _WinAPI_GetWindowLong($hWnd, $GWL_EXSTYLE)]

			If  $avCurrentStyles[0] <> Number($avStyles[0]) Or $avCurrentStyles[1] <> Number($avStyles[1]) Then
				_MakeWinFullscreenWindowed($hWnd)
				TrayTip("Note!", StringFormat('Made "%s" fullscreen windowed due to persistent setting!', WinGetTitle($hWnd)), 2)
			EndIf
			ExitLoop
		EndIf
		Sleep(1)
	Next
EndFunc

Func _timer()
	If $iTimer <> 0 Then
		_DbgPrint(StringFormat("Timer diff: %i", TimerDiff($iTimer)))
		$iTimer = 0
	Else
		$iTimer = TimerInit()
	EndIf
EndFunc

Func _PopulateUI()
	Local $aWindowList = _DetectWindowedMode()


	; Do some cleaning up of old items
;~ 	For $iv = $aMatchedWindows[0][0] To 1 Step -1
;~ 		If Not WinExists($aMatchedWindows[$iv][1]) Then ; Remove tray items for windows that no longer exist.
;~ 			TrayItemDelete($aMatchedWindows[$iv][0])
;~ 			_ArrayDelete($aMatchedWindows, $iv)
;~ 			$aMatchedWindows[0][0] = $aMatchedWindows[0][0]-1
;~ 			ContinueLoop
;~ 		EndIf
;~ 		Local $ivMatch = _ArraySearch($aWindowList, $aMatchedWindows[$iv][1], 1, $aWindowList[0])
;~ 		If $ivMatch == -1 Then ; Remove tray items for windows that no longer match the criteria.
;~ 			TrayItemDelete($aMatchedWindows[$iv][0])
;~ 			_ArrayDelete($aMatchedWindows, $iv)
;~ 			$aMatchedWindows[0][0] = $aMatchedWindows[0][0]-1
;~ 		Else ; Item matches, but is already added to item list
;~ 			_TestPersistent($aWindowList[$ivMatch]) ; ; Manage the persistent windows
;~ 			_ArrayDelete($aWindowList, $ivMatch); Delete from match list to not add duplicates
;~ 			$aWindowList[0] = $aWindowList[0]-1
;~ 		EndIf
;~ 		Sleep(1)
;~ 	Next

; The above is just so slow and adds nothing really, just redo everything instead.
	For $iv = $aMatchedWindows[0][0] To 1 Step -1
		TrayItemDelete($aMatchedWindows[$iv][0])
	Next
	$aMatchedWindows[0][0] = 0
	ReDim $aMatchedWindows[1][2]

	Local $ivTestPersistent = False
	If TimerDiff($iPersistentTimer) > 1000 Then $ivTestPersistent = True ; Check persistent windows once every second

;~ 	_timer()
	For $iv = 1 To $aWindowList[0]
		If $iDebugMode >= 2 Then _DbgPrint(StringFormat("Added window '%s' [%s] to menu.", WinGetTitle($aWindowList[$iv]), $aWindowList[$iv]))
		$aMatchedWindows[0][0] += 1
		ReDim $aMatchedWindows[$aMatchedWindows[0][0]+1][2]

		$aMatchedWindows[$aMatchedWindows[0][0]][1] = $aWindowList[$iv]
		$aMatchedWindows[$aMatchedWindows[0][0]][0] = TrayCreateItem(WinGetTitle($aWindowList[$iv]), $hMatchingMenu)
		TrayItemSetOnEvent(-1, "_MenuItemClicked")

		If $ivTestPersistent Then _TestPersistent($aWindowList[$iv]) ; ; Manage the persistent windows
		Sleep(1)
	Next
	If $ivTestPersistent Then $iPersistentTimer = TimerInit()
;~ 	_timer()
EndFunc

While 1
	Sleep(250)
	_PopulateUI()
WEnd
