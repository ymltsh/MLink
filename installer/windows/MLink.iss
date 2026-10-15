#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AssetSuffix
  #define AssetSuffix "local"
#endif
#ifndef ReleaseDir
  #error ReleaseDir is required
#endif

[Setup]
AppId={{49FD9C58-9034-4B75-A20C-B48BCD42E656}
AppName=妙联
AppVersion={#AppVersion}
AppPublisher=MLink
AppPublisherURL=https://github.com/ymltsh/MLink
DefaultDirName={localappdata}\Programs\MLink
DefaultGroupName=妙联
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\..\build\windows\installer
OutputBaseFilename=mlink-setup-{#AssetSuffix}
UninstallDisplayIcon={app}\code.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "*.zip,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\妙联"; Filename: "{app}\code.exe"
Name: "{autodesktop}\妙联"; Filename: "{app}\code.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\code.exe"; Description: "启动妙联"; Flags: nowait postinstall skipifsilent
