; Inno Setup: crea dist/No-Distraction-Setup-<versione>.exe
; Le definizioni AppVersion, WizardLarge e WizardSmall arrivano da prepare.py.
#include "generated.iss"

[Setup]
AppId={{EF03CDA4-7559-4283-BA40-4DD88DCB38CD}
AppName=No Distraction
AppVersion={#AppVersion}
AppVerName=No Distraction {#AppVersion}
AppPublisher=Andrea Ricciotti
AppPublisherURL=https://github.com/andrearicciotti1/nodistractiontool
AppSupportURL=https://github.com/andrearicciotti1/nodistractiontool
AppCopyright=© 2026 Andrea Ricciotti
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\No Distraction
DefaultGroupName=No Distraction
DisableProgramGroupPage=yes
; Installazione per l'utente corrente: niente richiesta di amministratore.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=No-Distraction-Setup-{#AppVersion}
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\NoDistraction.exe
UninstallDisplayName=No Distraction
WizardStyle=modern
WizardImageFile={#WizardLarge}
WizardSmallImageFile={#WizardSmall}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
italian.StartWithWindows=Avvia No Distraction con Windows
english.StartWithWindows=Start No Distraction with Windows
italian.OtherTasks=Altre opzioni:
english.OtherTasks=Other options:

[Tasks]
Name: "startup"; Description: "{cm:StartWithWindows}"; GroupDescription: "{cm:OtherTasks}"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\dist\NoDistraction\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\No Distraction"; Filename: "{app}\NoDistraction.exe"
Name: "{autodesktop}\No Distraction"; Filename: "{app}\NoDistraction.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "No Distraction"; ValueData: """{app}\NoDistraction.exe"" --background"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\NoDistraction.exe"; Description: "{cm:LaunchProgram,No Distraction}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/IM NoDistraction.exe /F"; Flags: runhidden; RunOnceId: "ChiudiApp"

[Code]
// L'avvio con Windows si può attivare anche dall'app: lo togliamo comunque
// alla disinstallazione.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'No Distraction');
end;
