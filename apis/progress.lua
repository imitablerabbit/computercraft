--[[
Progress lets a long job say how far along it is: layers of a quarry,
lines of a strip mine, blocks of a stack. report queues a
turtle_progress event on this computer. turtleagent picks those up and
sends the latest one to turtle control with its status, which shows it
as a progress bar on the turtle's screen. Without the agent nothing
happens and nothing is printed, so jobs can report as often as they
like (every block is fine).

  progress.report(3, 8, "layer 1 of 2")   3 of 8 done
  progress.report(nil, nil, "waiting")     no count, just what it is doing
  progress.clear()                         nothing to show any more

done and total are numbers (total nil when the end is not known); text
is a short line saying what is going on. The agent clears the progress
when a job ends, so jobs do not have to.
--]]

-- Say how far along the job is.
function report(done, total, text)
  os.queueEvent("turtle_progress", tonumber(done), tonumber(total), text ~= nil and tostring(text) or nil)
end

-- Nothing in progress any more.
function clear()
  os.queueEvent("turtle_progress_clear")
end
