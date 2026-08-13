; ============================================================================
;  Tor-Installer.iss
;  Zero-touch Tor SOCKS proxy installer — replicates the Dell "Mordad" setup
;  on other machines. Installs to C:\Tor, wraps tor.exe as an NSSM service
;  ("TorService"), opens the outbound firewall rule, sets it to auto-start,
;  and starts it. No manual steps after running the installer.
;
;  BEFORE COMPILING, put these files in a "Source" folder next to this
;  script (see the [Files] section below for exact paths):
;
;    Source\tor.exe                        (from Tor Expert Bundle, "Tor" folder)
;    Source\*.dll                           (all DLLs shipped alongside tor.exe
;                                             in the Expert Bundle — libssl-3.dll,
;                                             libcrypto-3.dll, libevent-2-*.dll,
;                                             zlib1.dll, etc.)
;    Source\geoip                           (OPTIONAL — from Expert Bundle's
;                                             "Data\Tor" folder, only needed for
;                                             country-based node filtering)
;    Source\geoip6                          (OPTIONAL, same folder as geoip)
;    Source\PluggableTransports\lyrebird.exe (from the same Expert Bundle)
;    Source\nssm.exe                        (win64 build, from nssm.cc)
;    Source\torrc                           (the torrc generated alongside
;                                             this script — bridges are no
;                                             longer hardcoded in here, see
;                                             Source\bridges.d\ below)
;    Source\bridges.d\README.txt            (explains the drop-in bridge
;                                             mechanism — ships to every
;                                             install)
;    Source\bridges.d\mordad-bridges.conf.sample  (this project's own
;                                             bridges, shipped INERT via the
;                                             .sample extension — rename to
;                                             .conf on a machine to activate)
;    Setup-TorService.ps1                   (the loggable post-install script —
;                                             keep it next to this .iss, NOT in
;                                             Source\; it's referenced directly)
;    Watchdog-TorAutoBridge.ps1              (auto-decides whether bridges are
;                                             needed and switches them on with
;                                             no manual .conf renaming — keep
;                                             next to this .iss too, registered
;                                             as a Scheduled Task by
;                                             Setup-TorService.ps1)
;
;  The actual NSSM/firewall/service work happens in Setup-TorService.ps1,
;  run via [Run] below through powershell.exe — NOT in Pascal [Code]. Pascal
;  Exec() failures inside CurStepChanged can fail completely silently under
;  /VERYSILENT, which is why file-copy-only-nothing-else symptoms happen.
;  (An earlier .cmd version of this script had the same "ran but nothing
;  visibly happened" problem when double-clicked directly — the console
;  window closes the instant the script finishes, so a fast failure looks
;  identical to doing nothing. The .ps1 version below pauses for Enter when
;  run interactively, and always writes to {app}\logs\install.log regardless,
;  so a truly silent failure — e.g. SmartScreen/AV blocking the script before
;  it even starts — is distinguishable from a fast one: if the log file has
;  no new entry at all, execution was blocked before it began.) It can also
;  be run standalone (as admin) on any machine where the installer already
;  copied files but the service never got created — no reinstall needed.
;
;  Build:   iscc.exe Tor-Installer.iss
;  Deploy silently to other machines (no UI at all):
;           Tor-Installer-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
; ============================================================================

#define MyAppName "Tor SOCKS Proxy"
#define MyAppVersion "1.0"
#define MyServiceName "TorService"
#define MyInstallDir "C:\Tor"

[Setup]
AppId={{B6C1B6C8-6B8B-4B7C-9B7B-A0057C500001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={#MyInstallDir}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableReadyPage=yes
DisableFinishedPage=no
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
OutputDir=Output
OutputBaseFilename=Tor-Installer-Setup
WizardStyle=modern
UninstallDisplayIcon={app}\tor.exe
SetupLogging=yes
; Force-close anything holding a lock on files we're about to overwrite
; (defense-in-depth; PrepareToInstall below handles our own service
; explicitly and more reliably than relying on this alone).
CloseApplications=force
RestartApplications=no

[Files]
; Core Tor binary + its DLLs
Source: "Source\tor.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "Source\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; GeoIP data (OPTIONAL — only needed if you use country-based node
; filtering like ExcludeNodes/ExcludeExitNodes in torrc; a plain SOCKS
; proxy works fine without it. Get from Expert Bundle's "Data\Tor"
; folder if you want it; safe to leave Source\ without these two files.)
Source: "Source\geoip"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "Source\geoip6"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; Pluggable transports (bridges)
Source: "Source\PluggableTransports\lyrebird.exe"; DestDir: "{app}\PluggableTransports"; Flags: ignoreversion

; NSSM (service wrapper)
Source: "Source\nssm.exe"; DestDir: "{app}"; Flags: ignoreversion

; Config
Source: "Source\torrc"; DestDir: "{app}"; Flags: ignoreversion

; Optional bridges drop-in folder (empty by default = no bridges, direct
; Tor connection). See Source\bridges.d\README.txt for the format.
Source: "Source\bridges.d\README.txt"; DestDir: "{app}\bridges.d"; Flags: ignoreversion
Source: "Source\bridges.d\mordad-bridges.conf.sample"; DestDir: "{app}\bridges.d"; Flags: ignoreversion

; Post-install script — does the actual NSSM/firewall/service work (see header)
Source: "Setup-TorService.ps1"; DestDir: "{app}"; Flags: ignoreversion

; Auto-bridge watchdog — decides on its own whether bridges are needed and
; switches them on, no manual .conf renaming required (registered as a
; Scheduled Task by Setup-TorService.ps1 above)
Source: "Watchdog-TorAutoBridge.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{app}\data"
Name: "{app}\logs"
Name: "{app}\bridges.d"

[Run]
; -Silent tells the script not to wait for a keypress when the installer
; itself launches it (only the standalone/manual double-click path should
; pause for Enter before closing).
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Setup-TorService.ps1"" -Silent"; WorkingDir: "{app}"; StatusMsg: "Configuring Tor service..."; Flags: runhidden waituntilterminated

[Code]
const
  FirewallRuleName = 'Tor SOCKS Proxy';

function RunHidden(const Exe, Params: string): Integer;
var
  ResultCode: Integer;
begin
  if not Exec(Exe, Params, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  Result := ResultCode;
end;

function ServiceExists(const ServiceName: string): Boolean;
begin
  Result := RunHidden('sc.exe', 'query "' + ServiceName + '"') = 0;
end;

function FirewallRuleExists(const RuleName: string): Boolean;
begin
  Result := RunHidden('netsh.exe', 'advfirewall firewall show rule name="' + RuleName + '"') = 0;
end;

function ServiceIsStopped(const ServiceName: string): Boolean;
var
  ResultCode: Integer;
begin
  // "sc query" output contains "STOPPED" while the service is down; findstr
  // returns 0 (match found) if so. If the service doesn't exist at all,
  // treat that as "stopped" too (nothing to wait for).
  if not ServiceExists(ServiceName) then
  begin
    Result := True;
    Exit;
  end;
  Exec(ExpandConstant('{cmd}'),
    '/c sc query "' + ServiceName + '" | findstr /i "STOPPED" >nul',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := ResultCode = 0;
end;

// Stops TorService (which also stops nssm.exe, since nssm.exe itself is the
// registered service process for NSSM-managed services — both nssm.exe and
// tor.exe are locked while the service is running) and force-kills any
// stragglers, so the upcoming [Files] copy doesn't silently fail to
// overwrite a locked binary. Called automatically before file copy starts.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Attempts: Integer;
begin
  Result := '';
  NeedsRestart := False;

  if ServiceExists('{#MyServiceName}') then
  begin
    RunHidden('sc.exe', 'stop "{#MyServiceName}"');

    // Wait up to ~10 seconds for the service (and nssm.exe with it) to
    // actually finish exiting, rather than assuming "stop" was instant.
    Attempts := 0;
    while (not ServiceIsStopped('{#MyServiceName}')) and (Attempts < 20) do
    begin
      Sleep(500);
      Attempts := Attempts + 1;
    end;
  end;

  // Backstop: force-kill any leftover processes regardless of service
  // state, in case something was running standalone (outside the service)
  // or the service was already in a broken/orphaned state.
  RunHidden('taskkill.exe', '/F /IM tor.exe /T');
  RunHidden('taskkill.exe', '/F /IM nssm.exe /T');

  // Brief settle time for the OS to fully release file handles after
  // process exit before Setup starts copying files over them.
  Sleep(500);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  NssmExe: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    NssmExe := ExpandConstant('{app}\nssm.exe');
    if ServiceExists('{#MyServiceName}') then
    begin
      RunHidden(NssmExe, 'stop {#MyServiceName}');
      RunHidden(NssmExe, 'remove {#MyServiceName} confirm');
    end;
    if FirewallRuleExists(FirewallRuleName) then
      RunHidden('netsh.exe', 'advfirewall firewall delete rule name="' + FirewallRuleName + '"');
    // Auto-bridge watchdog scheduled task - registered by Setup-TorService.ps1
    RunHidden('schtasks.exe', '/Delete /TN "TorAutoBridge-Watchdog" /F');
  end;
end;

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\logs"
