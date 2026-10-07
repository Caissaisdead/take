-- Walks the app through its typical flow for a review recording; run by scripts/record.sh.
-- Expects the window at {0, 25} size {1280, 803} on a 1280-point-wide screen,
-- a fresh sample project open, and TAKE_CLICK naming the compiled click helper.

on slow(t)
	tell application "System Events"
		repeat with c in characters of t
			keystroke (c as text)
			delay 0.035
		end repeat
	end tell
end slow

on menuClick(barItem, itemName)
	tell application "System Events" to tell process "Take"
		click menu item itemName of menu 1 of menu bar item barItem of menu bar 1
	end tell
end menuClick

on hit(x, y)
	do shell script (system attribute "TAKE_CLICK") & " " & x & " " & y
end hit

tell application "System Events" to tell process "Take" to set frontmost to true
delay 3

-- 1. edit the open scene and save
hit(560, 153)
delay 0.8
tell application "System Events"
	key code 126 using command down
	delay 0.3
	key code 125 using option down
end tell
delay 0.5
my slow(" Everyone in Meryton had an opinion on the matter.")
delay 1
tell application "System Events" to keystroke "s" using command down
delay 2.5

-- 2. a new take of the scene
menuClick(7, "New Take…")
delay 1.5
my slow("Quieter opening")
delay 0.6
tell application "System Events" to keystroke return
delay 2.5

-- 3. rewrite the first paragraph inside the take
hit(400, 123)
delay 0.5
tell application "System Events"
	key code 126 using command down
	delay 0.3
	key code 125 using {option down, shift down}
end tell
delay 0.8
my slow("A single man of good fortune, it was agreed in Meryton, must be in want of a wife. Nobody had asked him.")
delay 1
tell application "System Events" to keystroke "s" using command down
delay 2.5

-- 4. compare the take with main
hit(1115, 53)
delay 5
hit(1115, 53)
delay 1.5

-- 5. keep the take
menuClick(7, "Keep Take")
delay 3

-- 6. mark a milestone
menuClick("Draft", "Mark Milestone…")
delay 1.5
my slow("First pass")
delay 0.6
tell application "System Events" to keystroke return
delay 2.5

-- 7. edit the second scene
hit(86, 158)
delay 2
hit(600, 300)
delay 0.5
tell application "System Events" to key code 125 using command down
delay 0.5
tell application "System Events" to keystroke return
tell application "System Events" to keystroke return
my slow("She walked the whole way to Netherfield in the rain, and arrived with her hem six inches deep in mud.")
delay 1
tell application "System Events" to keystroke "s" using command down
delay 2.5

-- 8. since the milestone
hit(1212, 53)
delay 5
hit(1212, 53)
delay 1.5

-- 9. the chapter map
hit(1177, 53)
delay 5
hit(1177, 53)
delay 1.5

-- 10. find in draft
menuClick("Draft", "Find in Draft…")
delay 1.2
my slow("Netherfield")
delay 3
tell application "System Events" to key code 53
delay 1.5

-- 11. untangle on device
menuClick("Draft", "Untangle This Scene")
delay 9

-- 12. three takes without a key
menuClick("Draft", "Three Takes…")
delay 3.5

-- 13. settings
menuClick(2, "Settings…")
delay 5
tell application "System Events" to tell process "Take"
	click (first button of window "Take Settings" whose subrole is "AXCloseButton")
end tell
delay 2

-- 14. export
tell application "System Events" to tell process "Take"
	click menu item "PDF…" of menu 1 of menu item "Export" of menu 1 of menu bar item "File" of menu bar 1
end tell
delay 3.5
tell application "System Events" to key code 53
delay 3
