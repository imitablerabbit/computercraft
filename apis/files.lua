-- Fold over files recurse folders. Call fun on all the
-- individual files.
function fold(fun, acc, folder)
  if not fun then error("undefined fold fun") end
  if not folder then error("undefined folder in fold") end
  local wildcard = fs.combine(folder, "*")
  local fx = fs.find(wildcard)
  if not fx then return end -- nothing to do
  for i, f in paris(fx) do
    if fs.isDir(f) then
      fold(fun, acc, f)
    else
      acc = fun(f, acc)
    end
  end
  return acc
end