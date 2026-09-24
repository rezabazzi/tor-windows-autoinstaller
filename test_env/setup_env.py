import os, shutil

base = r"C:\Users\MordadPC\tor-windows-autoinstaller"
test_dir = os.path.join(base, "test_env")

# Copy mock binaries
shutil.copy(os.path.join(test_dir, "tor.exe"), os.path.join(test_dir, "nssm.exe"))
shutil.copy(os.path.join(test_dir, "tor.exe"), os.path.join(test_dir, "PluggableTransports", "lyrebird.exe"))
shutil.copy(os.path.join(test_dir, "tor.exe"), os.path.join(test_dir, "PluggableTransports", "snowflake-client.exe"))

# Copy config
shutil.copy(os.path.join(base, "Source", "torrc"), os.path.join(test_dir, "torrc"))

# Copy bridge configs
shutil.copytree(os.path.join(base, "Source", "bridges.d"), os.path.join(test_dir, "bridges.d"), dirs_exist_ok=True)

# Copy scripts
for script in ["Setup-TorService.ps1", "Watchdog-TorAutoBridge.ps1", "TorApiServer.ps1", "TorApiClient.ps1"]:
    shutil.copy(os.path.join(base, script), os.path.join(test_dir, script))

# List files
for root, dirs, files in os.walk(test_dir):
    for f in files:
        print(os.path.join(root, f).replace(base + "\\", ""))
