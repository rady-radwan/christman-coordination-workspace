; Inno Setup script for Christman Coordination Workspace (Windows).
; Built by GitHub Actions: ISCC.exe /DAppVersion=x.y.z installer/coordination.iss

#define AppName "Christman Coordination Workspace"
#define AppExe "christman_coordination.exe"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{4C7E2B19-9A3D-4F61-B8C2-6D1E0A5F3B47}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=The Christman Company
DefaultDirName={autopf}\Christman Coordination Workspace
DefaultGroupName=Christman Coordination Workspace
DisableProgramGroupPage=yes
; Installs for the current user without needing admin rights.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\dist
OutputBaseFilename=ChristmanCoordination-Setup-{#AppVersion}
SetupIconFile=..\assets\icon\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Registry]
; "christman-coord://" links (the sign-in email) open the app.
Root: HKA; Subkey: "Software\Classes\christman-coord"; ValueType: string; ValueName: ""; ValueData: "URL:Christman Coordination Workspace"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\christman-coord"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\christman-coord\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"
Root: HKA; Subkey: "Software\Classes\christman-coord\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
