# Computercraft APIs and commands 

Various APIs and commands for the computers and turtles in the Computercraft Minecraft mod.

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
