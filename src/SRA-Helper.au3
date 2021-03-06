#include <GUIConstantsEx.au3>
#include <SendMessage.au3>
#include <StringConstants.au3>
#include <TrayConstants.au3>
#include <WindowsConstants.au3>
#include <WinApi.au3>

HotKeySet("{PAUSE}", "terminate")
HotKeySet("{END}", "debug")

HotKeySet("{SPACE}", "hotKeyPress")
HotKeySet("{NUMPAD1}", "hotKeyPress")
HotKeySet("1", "hotKeyPress")

HotKeySet("{LEFT}", "hotKeyPress")
HotKeySet("{NUMPAD2}", "hotKeyPress")
HotKeySet("2", "hotKeyPress")

HotKeySet("{RIGHT}", "hotKeyPress")
HotKeySet("{NUMPAD3}", "hotKeyPress")
HotKeySet("3", "hotKeyPress")

HotKeySet("{NUMPAD0}", "hotKeyPress")
HotKeySet("{NUMPAD4}", "hotKeyPress")
HotKeySet("4", "hotKeyPress")

HotKeySet("{NUMPAD9}", "hotKeyPress")
HotKeySet("\", "hotKeyPress")

HotKeySet("{NUMPADDIV}", "hotKeyPress")
HotKeySet("{NUMPADMULT}", "hotKeyPress")
HotKeySet("{NUMPADSUB}", "hotKeyPress")
HotKeySet("{NUMPADADD}", "hotKeyPress")

While 1
	Sleep(200)
WEnd

; Handle the hotkeys being pressed
; AutoIt cannot handle function parameters so this function takes the pressed keycode and works out where to redirect to
Func hotKeyPress()
	; Do not operate on non-EndNote windows (or non-list EndNote windows)
	; NOTE: (?i) indicates case insensitive from that point onwards unless its in a group
	If IsEndNoteWIndow() = 0 then
		; Send the original space key since we hijacked it
		HotKeySet(@HotKeyPressed)
		Send(@HotKeyPressed)
		HotKeySet(@HotKeyPressed, "hotKeyPress");
		return
	EndIf

	Switch @HotKeyPressed
		Case "{SPACE}", "{NUMPAD1}", "1"
			moveToGroup(1)

		Case "{LEFT}", "{NUMPAD2}", "2"
			moveToGroup(2)

		Case "{RIGHT}", "{NUMPAD3}", "3"
			moveToGroup(3)

		Case "{NUMPAD0}", "{NUMPAD4}", "4"
			moveToGroup(4)

		case "{NUMPADDIV}"
			searchRef("institution")

		case "{NUMPAD9}", "\", "{NUMPADMULT}"
			searchRef("scholar")

		case "{NUMPADSUB}"
			searchRef("pubmed")
			
		case "{NUMPADADD}"
			searchRef("clipboard")
			TrayTip("SRA-Helper", "Copied seach to clipboard", 2, $TIP_ICONASTERISK + $TIP_NOSOUND)

		Case Else
			MsgBox(48, "SRA-Helper", "Unknown key sequence: " & @HotKeyPressed)
	EndSwitch
EndFunc

; Move the currently active reference to the group offset specified by $groupNo
Func moveToGroup($groupNo)
	Local $endNoteHwnd = WinGetHandle("[ACTIVE]")

	_SendMessage($endNoteHwnd, $WM_SETREDRAW, 0) ; Lock redrawing of the window to prevent flicker

	Send("!g") ; Open group menu
	Send("a") ; Skip down to "Add to Group" item
	Send("{DOWN}") ; Move down x1
	For $i = 1 To $groupNo
		Send("{DOWN}") ; Move down $groupNo times to the right group number
	Next
	Send("{ENTER}") ; Press Enter to confirm

	; BUGFIX: Hide + reshow the groups bar since EndNote doesn't update totals after a copy for some reason
	Send("!g")
	Send("h")
	Send("!g")
	Send("s")

	sleep(100)
	_SendMessage($endNoteHwnd, $WM_SETREDRAW, 1) ; Unlock redrawing of the window
	_WinAPI_RedrawWindow($endNoteHwnd, 0, 0, BitOr($RDW_INVALIDATE, $RDW_ALLCHILDREN, $RDW_ERASENOW)) ; Force total window repaint
EndFunc

Func searchRef($method)
	Local $clip

	ClipPut("") ; Clear the clipboard so we know we can check against blanks
	Sleep(100) ; Wait for Clipboard to unlock (for some reason it takes time to do this)

	Send("^k") ; Copy ref to clipboard via EndNote

	; Keep asking the clipboard for contents until it returns non-null (only for 10 tries though)
	For $i = 1 to 10
		$clip = ClipGet() ; Extract copied reference from keyboard
		If ($clip <> "") Then ExitLoop
		Sleep(100) ; Sleep for 100ms
	Next

	If ($clip == "") Then
		MsgBox(16, "SRA-Helper", "EndNote failed to provide a reference when asked. Maybe you don't have anything selected?")
	Else
		; Tidy up ref so its just the title
 		Local $refExtracted = StringStripCR($clip) ; Remove all Chr(13)
		$refExtracted = StringReplace($refExtracted, Chr(10), '') ; Remove remaining windows CR junk
		$refExtracted = StringRegExpReplace($refExtracted, '^.+"(.+?)".*', '$1') ; Scrap everything not in speachmarks
		$refExtracted = StringStripWS($refExtracted, $STR_STRIPLEADING + $STR_STRIPTRAILING + $STR_STRIPSPACES) ; Remove fore / aft / double whitespace
		$refExtracted = StringRegExpReplace($refExtracted, '\.$', '') ; Remove final punctuation from string

		If ($refExtracted = "") Then
			MsgBox(16, "SRA-Helper", "Sorry but I can't understand that reference format. Make sure 'Annotated' is selected as the reference format")
		Else
			; Make the ref URL ready
			Local $refExtractedURL = StringReplace($refExtracted, " ", "+")
			$refExtractedURL = StringRegExpReplace($refExtractedURL, "[\.]", "")

			Switch String($method)
				Case "scholar"
					ShellExecute("https://scholar.google.com/scholar?q=" & $refExtractedURL)
				Case "institution"
					Local $localUrl = "";
					; @ifdef MONASH
					$localUrl = "http://monash.hosted.exlibrisgroup.com/primo_library/libweb/action/search.do?fn=search&ct=search&initialSearch=true&vid=MON&vl%281UIStartWith0%29=contains&vl%28freeText0%29=" & $refExtractedURL
					; @endif
					; @ifdef QH
					$localUrl = "http://qhlibraries.slq.qld.gov.au/primo-explore/jsearch?query=any,contains," & $refExtractedURL & "&tab=jsearch_slot&vid=HHS&lang=en_US&offset=0&journals=any," & $refExtractedURL
					; @endif

					; Fall through to defaulting to Bond if we're in debug mode (i.e. no pre-process step)
					; @ifdef BOND
					$localUrl = "https://librarysearch.bond.edu.au/discovery/search?query=any%2Ccontains%2C" & $refExtractedURL & "&tab=Everything&search_scope=Everything&vid=61BOND_INST%3ABOND&offset=0"
					; @endif
					ShellExecute($localUrl)
				Case "pubmed"
					ShellExecute("https://www.ncbi.nlm.nih.gov/pubmed/?term=" & $refExtractedURL)
				Case "clipboard"
					ClipPut($refExtracted)
			EndSwitch
		EndIf
	EndIf
EndFunc

; Returns whether the currently active window looks like an EndNote library view
; This function will also scan all MDI children
; @return Number 0=Not an EndNote window, 1=Is an EndNote list thats maximized, 2=MDI child list
Func IsEndNoteWindow()
	Local $title = WinGetTitle("[ACTIVE]")
	If StringRegExp($title, "^EndNote X[789] - \[.*\]$") Then
		Return 1
	ElseIf $title = "EndNote X7" Then
		Local $activeChild = _WinAPI_GetWindow(WinGetHandle("[ACTIVE]"), $GW_CHILD)
		If Not $activeChild Then Return false

		Local $childText = WinGetText($activeChild)
		If Not $childText Then Return false

		If StringRegExp($childText, "^.*\.(?i)enl\n") Then Return 2

		Return 0
	EndIf
EndFunc

Func debug()
	Local $output = "Active Window title is [" & WinGetTitle("[ACTIVE]") & "]" & Chr(10) & Chr(10)
	Local $isEndNote = IsEndNoteWindow()

	If $isEndNote = 0 Then
		$output &= "Which SRA-Helper WILL NOT handle"
	ElseIf $isEndNote = 1 Then
		$output &= "Which SRA-Helper WILL handle (maximized list view)"
	ElseIf $isEndNote = 2 Then
		$output &= "Which SRA-Helper WILL handle (restored MDI child list view)"
	Else
		$output &= "Which SRA-Helper WILL handle (unknown response)"
	EndIf

	MsgBox(64, "SRA-Helper", $output)
EndFunc

Func terminate()
	Exit
EndFunc
