cd C:\Users\MordadPC\tor-windows-autoinstaller
Copy-Item test_env\tor.exe test_env\nssm.exe
Copy-Item test_env\tor.exe test_env\PluggableTransports\lyrebird.exe
Copy-Item test_env\tor.exe test_env\PluggableTransports\snowflake-client.exe
Copy-Item Source\torrc test_env\torrc -Force
Copy-Item Source\bridges.d\* test_env\bridges.d\ -Force -Recurse
Copy-Item Setup-TorService.ps1 test_env\
Copy-Item Watchdog-TorAutoBridge.ps1 test_env\
Copy-Item TorApiServer.ps1 test_env\
Copy-Item TorApiClient.ps1 test_env\
Get-ChildItem test_env -Recurse -File | Select-Object FullName
