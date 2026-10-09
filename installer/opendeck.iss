; Windows installer for OpenDeck (Inno Setup 6).
; Built by .github/workflows/release.yml:
;   iscc /DAppVersion=0.1.0 installer\opendeck.iss
; Expects the Flutter release build in build\windows\x64\runner\Release.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F0C8E52-3D7A-4B8E-9A61-0D5C2E7B4F19}
AppName=OpenDeck
AppVersion={#AppVersion}
AppPublisher=OpenDeck contributors
AppPublisherURL=https://github.com/Introvert-Programmer-Lab/opendeck
AppSupportURL=https://github.com/Introvert-Programmer-Lab/opendeck/issues
DefaultDirName={autopf}\OpenDeck
DefaultGroupName=OpenDeck
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=OpenDeck-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\opendeck.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Per-user install by default, no admin prompt; the dialog offers all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startup"; Description: "Start OpenDeck when I sign in"; GroupDescription: "Other:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\OpenDeck"; Filename: "{app}\opendeck.exe"
Name: "{autodesktop}\OpenDeck"; Filename: "{app}\opendeck.exe"; Tasks: desktopicon
Name: "{userstartup}\OpenDeck"; Filename: "{app}\opendeck.exe"; Tasks: startup

[Run]
Filename: "{app}\opendeck.exe"; Description: "{cm:LaunchProgram,OpenDeck}"; Flags: nowait postinstall skipifsilent
