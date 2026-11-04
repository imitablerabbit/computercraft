# Computercraft APIs and commands 

Various APIs and commands for the computers and turtles in the Computercraft Minecraft mod.

## Turtle control monitor

`turtlecontrol` is a touch dashboard for mining turtles. It runs on a
computer that has a wireless modem and an advanced monitor attached (touch
only works on advanced monitors). The main screen shows an icon for every
turtle it can hear, coloured by what the turtle is doing: green when idle,
orange with a pickaxe while a job runs, red after a job fails and gray once
the turtle has gone quiet. Touch an icon to open that turtle's screen, which
shows its state and fuel and has buttons for the jobs in `apis/turtlectl.lua`
(strip mine, mine line, logger, refuel) plus Stop and Back.

Setup:

1. On each turtle, attach a wireless modem and run `turtleagent`. It
   broadcasts its status every 5 seconds, answers the monitor's requests and
   runs the job it is told to. Label the turtle first (`label set Digger`)
   so the dashboard shows a name instead of an ID.
2. On the monitor computer, run `turtlecontrol`. Optional arguments are the
   monitor side, the text scale (default 0.5) and a registry file from
   `registrylistener`, whose turtles are shown as offline until heard from.

```
turtlecontrol [monitorSide] [textScale] [registryFile]
turtleagent [heartbeatSeconds]
```

Stop aborts the running job on the turtle, which is left wherever it got to.
The job buttons use the default arguments from the catalogue in
`apis/turtlectl.lua`; edit that table to change them or add jobs.

## Installing on a computer in game

The game can only fetch files over HTTP with `wget`, so this repo ships a
tiny server that hosts it from your own machine. It needs nothing beyond
Python 3.

On your machine, from this folder:

```bash
python3 serve.py
```

It listens on port 8080 (change with `-p`) and prints the exact command to
run in game, which is:

```
wget run http://<your-ip>:8080/install.lua
```

That downloads every `.lua` file into the same paths on the computer and
saves the installer as `update.lua`, so after the first install you can
just run `update` to pull the latest copies. Reboot afterwards so
`startup.lua` loads the new APIs.

Single files work too:

```
wget http://<your-ip>:8080/programs/turtle/stripmine.lua programs/turtle/stripmine.lua
```

`/files.txt` lists everything the server will hand out.

### If `wget` says the domain is blocked or the request fails

ComputerCraft refuses local and private addresses by default. For
CC: Tweaked, edit `computercraft-server.toml` (under `config/` on a server,
or `saves/<world>/serverconfig/` for single player) and either remove the
rule that denies `$private`, or add an allow rule above it:

```toml
[[http.rules]]
host = "<your-ip>"
action = "allow"
```

Older ComputerCraft versions use an `http_blacklist` line in
`computercraft.cfg` instead; remove the private ranges from it. Restart
the world or server afterwards.

### Running the server under WSL

Minecraft on the Windows side can reach the server at `http://localhost:8080`
or at the WSL address that `serve.py` prints. The WSL address changes on
reboot, so just run `update` with the new URL if the old one stops working:

```
update http://<new-ip>:8080/
```

Other machines on the LAN cannot see WSL directly. Either run `serve.py`
from Windows Python instead, or forward the port from PowerShell as admin
and allow it through the firewall:

```powershell
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=<wsl-ip>
```
