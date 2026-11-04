# GUI

GUI is a lua computercraft api for creating gui applications in computercraft.

Components: GUIRootContainer (the window, with optional title bar and close
button), GUIText (a label), GUIButton (press listeners), GUIInput (a text
field), GUITurtleIcon (a turtle picture with its state), GUIInventoryGrid (a
turtle's slots) and GUIDropdown (one value picked from a list that opens on
touch, with select listeners). Every component is positioned with
setPreferredBounds before being added to its parent.