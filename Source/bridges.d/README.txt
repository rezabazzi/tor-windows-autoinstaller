bridges.d\ — bridge config, activated AUTOMATICALLY when needed
==================================================================

You don't need to touch this folder by hand anymore. A scheduled task
("TorAutoBridge-Watchdog", installed automatically, runs every 5 min +
at boot) watches C:\Tor\logs\tor-notice.log and decides on its own:

  - If Tor bootstraps to 100% without bridges -> does nothing, stays off.
  - If Tor is stuck (no "Bootstrapped 100%") for ~15 minutes with bridges
    OFF -> it finds the first *.conf.sample in this folder, strips the
    ".sample" to activate it, and restarts TorService automatically.
  - If bridges are already ON and it's STILL stuck ~15 minutes later ->
    it logs one alert to logs\autobridge.log and stops restarting (to
    avoid a restart loop chasing bridges that can't work) - that's the
    point at which a human needs to drop in fresh bridge lines, since
    the watchdog can only switch between "no bridges" and whatever
    bridge files already exist on disk, not invent new working ones.

torrc includes this folder automatically via:

    %include C:\Tor\bridges.d\*.conf

So the only thing you ever need to do manually is keep at least one
current *.conf.sample here as a fallback - the watchdog handles turning
it on and restarting the service by itself.

Format for a bridge conf (same whether it's a .sample or already active):

    UseBridges 1
    ClientTransportPlugin webtunnel,obfs4 exec C:\Tor\PluggableTransports\lyrebird.exe

    Bridge webtunnel <ip>:<port> <fingerprint> url=<url> ver=<ver>
    Bridge obfs4 <ip>:<port> <fingerprint> cert=<cert> iat-mode=<0|1|2>

Bridge lines age out (relays get blocked/rotated) - get fresh ones from
https://bridges.torproject.org/ or a trusted contact periodically, and
replace mordad-bridges.conf.sample (or whichever .sample is stale) so the
watchdog has something current to fall back on next time it's needed.

A filled-in example (this project's own bridges, as of Aug 2026) ships as
mordad-bridges.conf.sample right next to this README - it will be
auto-activated the first time direct connections get stuck, no action
needed from you.

Manual override: to force bridges on/off right now instead of waiting for
the watchdog, activate/remove the .conf yourself and run
`nssm restart TorService` - the watchdog won't fight you, it only acts
after ~15 minutes of a stuck bootstrap.

