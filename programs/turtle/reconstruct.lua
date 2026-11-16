--[[
Reconstruct feeds blocks from a chest, one at a time, to a machine that
changes the block in front of the turtle on a redstone pulse (such as an
atomic reconstructor with a lens of the miner turning netherrack into
nether ores and ancient debris), digs the result and drops it into
another chest. Put the turtle with the input chest behind it, the output
chest on its right and the redstone line to the machine on its left,
aimed at the block in front of the turtle. See apis/reconstruct.lua.

Usage: reconstruct [input] [output] [pulse] [stacks] [delay]
  input   where the chest of blocks is: left, right, behind, below, above
  output  where the chest for the results is
  pulse   the turtle side wired to the machine: left, right, back, top, bottom
  stacks  how many stacks to do, 0 for no limit
  delay   seconds between the pulse and checking the block
--]]

local args = {...}
if #args > 5 then
  print("Usage: reconstruct [input] [output] [pulse] [stacks] [delay]")
  return
end

local ok, err = reconstruct.run({ input = args[1], output = args[2], pulse = args[3], stacks = args[4], delay = args[5] })
if not ok then error(err, 0) end
