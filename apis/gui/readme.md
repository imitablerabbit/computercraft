# GUI

GUI is a lua computercraft api for creating gui applications in computercraft.

Components: GUIRootContainer (the window, with optional title bar and close
button), GUIText (a label), GUIButton (press listeners), GUIInput (a text
field), GUITurtleIcon (a turtle picture with its state), GUIInventoryGrid (a
turtle's slots), GUIDropdown (one value picked from a list that opens on
touch, with select listeners), GUICheckbox ([x] with a label, toggled on
touch, with change listeners) and GUIScrollPane (a window onto taller
content with a scrollbar; clicks reach the content only inside the pane).

Layouts: any component can be a container. Give it a layout with
setLayout and it places its children itself: GUIBoxLayout stacks them
vertically or horizontally (fixed children keep their preferred size on
that axis, children with setFlex share the rest, and all stretch across
unless setStretch(false)), GUIGridLayout uses equal cells. A layout starts
from each child's preferred size, which is the size given to
setPreferredBounds, and a container's own preferred size is what its layout
needs (getPreferredSize), which is how a scroll pane learns how tall its
content is. Components placed by a layout are given their bounds with
setBounds, which does not change their preferred size. Every component is positioned with
setPreferredBounds before being added to its parent.