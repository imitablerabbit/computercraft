# GUI

GUI is a lua computercraft api for creating gui applications in computercraft.

Components: GUIRootContainer (the window, with optional title bar and close
button), GUIText (a label), GUIButton (press listeners), GUIInput (a text
field), GUITurtleIcon (a turtle picture with its state), GUIInventoryGrid (a
turtle's slots), GUIDropdown (one value picked from a list that opens on
touch, with select listeners), GUICheckbox ([x] with a label, toggled on
touch, with change listeners) and GUIScrollPane (a window onto taller
content with a scrollbar; clicks reach the content only inside the pane).

Meters and lists:
- GUIProgressBar: a horizontal bar for value of max (setValue, setMax,
  setProgress(value, max, label)), with a label or percentage drawn over
  it, fill and empty colours, and setWarnBelow(value) to turn it the warn
  colour when low (fuel going red).
- GUIGauge: a compact level meter, vertical (label on top, number at the
  bottom) or horizontal (label, meter, number), for energy or tank levels:
  setRange(min, max), setValue, setLabel, setWarnBelow, setFormat(fn).
- GUISparkline: a tiny chart of the last samples (push(value), setSamples),
  one column per sample in thirds of a character, scaled to the samples or
  setRange(min, max); setShowRange(true) writes the highest and lowest down
  the left side.
- GUITabs: a tab strip over a content area. addTab(title, component),
  select(index) or a touch on a title, change listeners (index, title).
  Only the selected tab's component is in the tree, so only it draws and
  gets events. setStripReserve(n) keeps the right end of the strip free
  for a button added to the tabs.
- GUIDialog: a modal box in the middle of the screen with a title, a
  wrapped message and buttons; show(component) opens it over that
  component's screen. While open it captures every click, touch and key,
  and is drawn again whenever something underneath repaints. A button
  closes it and runs its function. guidialog.confirm(component, title,
  message, onYes, onNo, { yes, no, danger }) and guidialog.alert(component,
  title, message, onOk) make the usual two.
- GUITable: a list view with columns ({ title, width } or { title, flex },
  align, key), rows of values (setRows, addRow) that scroll inside it, a
  touch on a column title sorts by it (again to reverse), a touch on a row
  selects it (select listeners get index and row), and per-row colours
  from a row's color and background fields. Its GUITableModel keeps the
  rows, sort and selection.

Layouts: any component can be a container. Give it a layout with
setLayout and it places its children itself: GUIBoxLayout stacks them
vertically or horizontally (fixed children keep their preferred size on
that axis, children with setFlex share the rest, and all stretch across
unless setStretch(false)), GUIGridLayout uses equal cells. A layout starts
from each child's preferred size, which is the size given to
setPreferredBounds, and a container's own preferred size is what its layout
needs (getPreferredSize), which is how a scroll pane learns how tall its
content is. Components placed by a layout are given their bounds with
setBounds, which does not change their preferred size. The newer
components have sensible preferred sizes of their own (a bar is one row).

Themes: guitheme names colours by role (background, surface, text, muted,
border, header, accent, button, field, highlight, danger, warn, ok, fill,
track and their text colours) and has a dark and a light theme.
Components take their default colours from the theme; colours a program
sets itself are kept. guitheme.setTheme(name) picks the theme for
components made from then on and guitheme.apply(root) recolours an
existing tree (guitheme.use(name, root) does both). Until a program picks
a theme, plain components (containers, text, buttons, inputs, the root)
keep their classic white look, so older programs look as they did.
guitheme.fit(display, minW, minH) picks the largest monitor text scale
that still gives minW x minH characters and returns { scale, w, h,
compact }; guitheme.isCompact(w, h) says whether a screen is narrow (under
40 columns or 16 rows, like a pocket computer) and wants the compact
layout.

Building from a table: guibuild.build(spec) turns a nested table such as
{ type = "box", dir = "vertical", gap = 1, children = { { type = "text",
text = "Hi", id = "title" }, { type = "button", text = "Go", flex = 1,
onPress = fn } } } into the component tree and returns the top component
and a table of the components that have an id. It knows every component
type (root, box, panel, grid, scroll, tabs, text, button, input, checkbox,
dropdown, progress, gauge, sparkline, table, turtleicon, inventory and
dialog), common fields (w, h, flex, stretch, border, bg, fg, bgRole,
fgRole, visible, init) and each type's own; see the comment at the top of
guibuild.lua. guibuild.register adds more types.

Text typed on a computer reaches components as char events (addCharListener)
alongside key events; GUIInput uses both. See programs/gui/examples for
worked examples of every component (widgets.lua shows the meters, tabs,
dialogs, table and theme switching; form.lua is built with guibuild).
Every component is positioned with setPreferredBounds before being added
to its parent, unless guibuild or a layout places it.
