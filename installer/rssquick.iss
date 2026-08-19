; RSS Quick installer.
;
; Built by build/publish.ps1, which passes every value in via /D. Compile it by hand with:
;   ISCC.exe /DAppVersion=1.1.0 /DArch=x64 /DSourceDir=... /DOutputDir=... installer\rssquick.iss
;
; The payload is a self-contained build, so there is no .NET prerequisite to detect, download
; or explain. That is the whole reason this installer has no dependency-bootstrap logic.

#ifndef AppVersion
  #error AppVersion must be defined (pass /DAppVersion=x.y.z)
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef SourceDir
  #error SourceDir must be defined (pass /DSourceDir=path-to-published-files)
#endif
#ifndef OutputDir
  #define OutputDir "..\artifacts"
#endif

#if Arch == "arm64"
  #define ArchAllowed "arm64"
#else
  #define ArchAllowed "x64compatible"
#endif

[Setup]
; Stable across versions and across architectures, so an upgrade replaces the previous install
; instead of registering a second product beside it.
AppId={{5E4A8895-C857-4BD4-AD08-2DD5F8CC2533}
AppName=RSS Quick
AppVersion={#AppVersion}
AppVerName=RSS Quick {#AppVersion}
AppPublisher=Kelly Ford
AppPublisherURL=https://github.com/kellylford/rssquick
AppSupportURL=https://github.com/kellylford/rssquick/issues
AppUpdatesURL=https://github.com/kellylford/rssquick/releases
VersionInfoVersion={#AppVersion}

DefaultDirName={autopf}\RSS Quick
DefaultGroupName=RSS Quick
LicenseFile={#SourceDir}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=RSSQuick-{#AppVersion}-setup-win-{#Arch}
UninstallDisplayName=RSS Quick
UninstallDisplayIcon={app}\RSSQuick.exe

; Install for the current user by default, so the common case never raises a UAC prompt.
; A UAC prompt is one more thing to get past, and nothing here needs administrator rights.
; An administrator can still choose an all-users install on the first wizard page.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

ArchitecturesAllowed={#ArchAllowed}
ArchitecturesInstallIn64BitMode={#ArchAllowed}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The welcome page carries no information the title bar does not. Every page removed is a page
; a screen reader user does not have to read before getting to a decision.
DisableWelcomePage=yes
DisableProgramGroupPage=yes
ShowLanguageDialog=no

; Blocks installing over a running copy, which would otherwise fail on a locked executable
; and leave a half-updated install. Matches the mutex the application creates at startup.
AppMutex=RSSQuick.SingleInstance

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\RSSQuick.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\LICENSE";      DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\README.md";    DestDir: "{app}"; Flags: ignoreversion

; The sample feed list. onlyifdoesntexist so an upgrade never overwrites a list the user has
; edited in place - RSS Quick reads the copy next to the executable when the working directory
; has none, which is exactly the case for a Start Menu shortcut.
Source: "{#SourceDir}\RSS.opml"; DestDir: "{app}"; Flags: onlyifdoesntexist uninsneveruninstall

[Icons]
Name: "{group}\RSS Quick"; Filename: "{app}\RSSQuick.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall RSS Quick"; Filename: "{uninstallexe}"
Name: "{autodesktop}\RSS Quick"; Filename: "{app}\RSSQuick.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\RSSQuick.exe"; Description: "Start RSS &Quick"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; RSS.opml is installed uninsneveruninstall so an edited list survives an upgrade; remove it on
; uninstall only if it is still the untouched copy we shipped.
Type: files; Name: "{app}\RSS.opml"
Type: dirifempty; Name: "{app}"
