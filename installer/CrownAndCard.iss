; SPDX-License-Identifier: AGPL-3.0-or-later
;
; Crown & Card installer (Inno Setup 6). Built by launcher\build.ps1 -Package:
;   ISCC.exe /DAppVersion=0.26.001 /DNumericVersion=0.26.1.0 installer\CrownAndCard.iss
; It packages dist\CrownAndCard\ into dist\CrownAndCard-Setup-<version>.exe.
;
; Per-user install (no administrator rights) into %LOCALAPPDATA%\Programs\CrownAndCard,
; with Start menu / optional desktop shortcuts and a normal uninstaller. The
; launcher offers newer releases by downloading and running this same setup.

#ifndef AppVersion
  #error Pass /DAppVersion=0.YY.BBB (launcher\build.ps1 does this)
#endif
#ifndef NumericVersion
  #define NumericVersion "0.0.0.0"
#endif

[Setup]
AppId={{6F3A9C2E-5B1D-4E7A-9C44-2D8B1F0E7A61}
AppName=Crown & Card
AppVersion={#AppVersion}
AppVerName=Crown & Card {#AppVersion}
AppPublisher=David Kendig
AppPublisherURL=https://github.com/DavidKendig/CrownAndCard
AppSupportURL=https://github.com/DavidKendig/CrownAndCard/issues
AppUpdatesURL=https://github.com/DavidKendig/CrownAndCard/releases
VersionInfoVersion={#NumericVersion}
VersionInfoProductName=Crown & Card
VersionInfoDescription=Crown & Card Setup
PrivilegesRequired=lowest
DefaultDirName={autopf}\CrownAndCard
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
SetupIconFile=..\launcher\assets\launcher.ico
UninstallDisplayIcon={app}\CrownAndCardLauncher.exe
UninstallDisplayName=Crown & Card
Compression=lzma2/max
SolidCompression=yes
; Close a running launcher through Windows Restart Manager (it asks first) when updating.
CloseApplications=yes
RestartApplications=no
OutputDir=..\dist
OutputBaseFilename=CrownAndCard-Setup-{#AppVersion}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\dist\CrownAndCard\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Crown & Card"; Filename: "{app}\CrownAndCardLauncher.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Crown & Card"; Filename: "{app}\CrownAndCardLauncher.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\CrownAndCardLauncher.exe"; Description: "{cm:LaunchProgram,Crown & Card}"; Flags: nowait postinstall skipifsilent
