; Single-file installer for the Windows build: iscc windows\installer.iss /DSourceDir=out\Kitsune /DAppVersion=1.8.1
[Setup]
AppId={{6B1C0F52-5A5B-4C21-9C3E-4B7F0E7A9D11}
AppName=Kitsune
AppVersion={#AppVersion}
AppPublisher=Kitsune
DefaultDirName={autopf}\Kitsune
DefaultGroupName=Kitsune
OutputDir=..\out
OutputBaseFilename=Kitsune-Setup
SetupIconFile=Kitsune.App\Assets\Kitsune.ico
UninstallDisplayIcon={app}\Kitsune.exe
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=force

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать значок на рабочем столе"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Kitsune"; Filename: "{app}\Kitsune.exe"
Name: "{autodesktop}\Kitsune"; Filename: "{app}\Kitsune.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Kitsune.exe"; Description: "Запустить Kitsune"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/delete /tn Kitsune /f"; Flags: runhidden; RunOnceId: "RemoveAutostart"
