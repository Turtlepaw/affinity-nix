{
  linkFarm,
  fetchurl,
  writeText,
  runCommand,
  callPackage,
  xvfb-run,
  lib,
  inputs,
  wine-packages,
  pkgs,
  ...
}:
let
  verbs = [
    #"tahoma"
    "vcrun2022"
    "dotnet20"
    "dotnet48"
    #"corefonts"
    "win11"
  ];

  inherit (wine-packages)
    wine
    winetricks
    wineserver
    ;

  dependencies = callPackage ./dependencies.nix { };
  winetricksCache = linkFarm "winetricks-cache" [
    {
      name = "vcrun2022/vc_redist.x64.msi";
      path = fetchurl {
        url = "https://aka.ms/vs/17/release/vc_redist.x64.msi";
        hash = "sha256-LITBleYUHCruG6dNBwQr0FEXIfhNzXBYWBalSfzdbA0="; # Nix will give us the real hash
      };
    }
    {
      name = "vcrun2022/vc_redist.x86.msi";
      path = fetchurl {
        url = "https://aka.ms/vs/17/release/vc_redist.x86.msi";
        hash = "sha256-EAafJbfNcv2BIXJoed5iegazClsx4GOkkWQUzJ4s7Qc="; # Nix will give us the real hash
      };
    }
    # Keep the .NET installers as they are for now
    {
      name = "dotnet48/ndp48-x86-x64-allos-enu.exe";
      path = fetchurl {
        urls = [
          "https://web.archive.org/web/20260313001348/https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe"
          "https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe"
        ];
        hash = "sha256-lYidbePyBwwHeQrWzyAA0z2aG9/Go4FyWrgqscMU/VM=";
      };
    }
    {
      name = "dotnet20/NetFx64.exe";
      path = fetchurl {
        urls = [
          "https://web.archive.org/web/20060509045320/https://download.microsoft.com/download/a/3/f/a3f1bf98-18f3-4036-9b68-8e6de530ce0a/NetFx64.exe"
          "https://download.microsoft.com/download/a/3/f/a3f1bf98-18f3-4036-9b68-8e6de530ce0a/NetFx64.exe"
        ];
        hash = "sha256-fqhtyo7q7cqkoXNwVHyizqnptndJcrjgPSyx+w55hmk=";
      };
    }
  ];

  layer_1 = runCommand "affinity-prefix-layer-1" { } ''
    set -x -e
    mkdir -p $out
    export WINEPREFIX="$out"
    export WINETRICKS_UPDATE_CHECK=0
    export WINETRICKS_LATEST_VERSION_CHECK=disabled

    mkdir -p /tmp/cache
    export XDG_CACHE_HOME="/tmp/cache"

    ${lib.getExe wine} wineboot --update

    # by diffing a registry dump we found that you can disable the file association
    # through a registry key.
    ${lib.getExe wine} regedit /S "${(writeText "file-association-disable.reg" ''
      Windows Registry Editor Version 5.00

      [HKEY_CURRENT_USER\Software\Wine\DllOverrides]
      "winemenubuilder.exe"=""

      [HKEY_CURRENT_USER\Software\Wine\FileOpenAssociations]
      "Enable"="N"
    '').outPath}"

    # Vulkan renderer setup currently fails with WoW64 Wine because
    # winetricks invokes C:\windows\syswow64\regedit.exe.

    install -D -t "$WINEPREFIX/drive_c/windows/system32/WinMetadata/" ${inputs.windows-rs}/crates/libs/bindgen/default/Windows.winmd

    ${lib.getExe wineserver} -w
  '';

  layer_2 =
    runCommand "affinity-prefix-layer-2-edgewebview"
      {
        nativeBuildInputs = [
          xvfb-run
          pkgs.cabextract # Make sure pkgs is in scope, or use inputs.nixpkgs.legacyPackages.${system}.cabextract
        ];
      }
      ''
        set -x -e

        mkdir -p $out
        cp -a ${layer_1}/. $out
        chmod -R +w $out
        export WINEPREFIX="$out"

        mkdir -p /tmp/cache
        export XDG_CACHE_HOME="/tmp/cache"

        ${lib.getExe wine} winecfg -v win7

        # --- Extract Fixed Version CAB directly into the prefix ---
        mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/"
        ${lib.getExe pkgs.cabextract} -d "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/" "${dependencies}/Microsoft.WebView2.FixedVersionRuntime.133.0.3065.92.x64.cab"

        ${lib.getExe wine} winecfg -v win11

        ${lib.getExe wine} regedit /S "${(writeText "webview2-regedit-changes.reg" ''
          Windows Registry Editor Version 5.00

          [HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\edgeupdate]
          "Start"=dword:00000004

          [HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\edgeupdatem]
          "Start"=dword:00000004

          [HKEY_CURRENT_USER\Software\Wine\AppDefaults]

          [HKEY_CURRENT_USER\Software\Wine\AppDefaults\msedgewebview2.exe]
          "Version"="win7"

          # --- Register the Fixed Version Runtime (Updated to 133.0.3065.92) ---
          [HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}]
          "pv"="133.0.3065.92"
          "name"="Microsoft Edge WebView2 Runtime"
        '').outPath}"

        ${lib.getExe wineserver} -w
      '';
in
runCommand "affinity-prefix-layer-3-winetricks"
  {
    nativeBuildInputs = [
      xvfb-run
      pkgs.cabextract
      pkgs.msitools # Provides the msiextract tool
    ];
  }
  ''
    set -x -e

    mkdir -p /tmp/cache/winetricks/corefonts

    mkdir -p $out
    cp -a ${layer_2}/. $out
    chmod -R +w $out
    export WINEPREFIX="$out"

    export XDG_CACHE_HOME="/tmp/cache"
    export WINETRICKS_UPDATE_CHECK=0
    export WINETRICKS_LATEST_VERSION_CHECK=disabled

    export WINEDEBUG=-all
    export WINEESYNC=0
    export WINEFSYNC=0

    cp -R ${winetricksCache}/* /tmp/cache/winetricks
    cp -R ${inputs.corefonts}/*.exe /tmp/cache/winetricks/corefonts

    # 1. Extract VC++ 2022 DLLs directly into system directories (bypasses msiexec bug)
    mkdir -p "$WINEPREFIX/drive_c/windows/system32"
    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"

    ${pkgs.msitools}/bin/msiextract --directory "$WINEPREFIX/drive_c/windows/system32" /tmp/cache/winetricks/vcrun2022/vc_redist.x64.msi
    ${pkgs.msitools}/bin/msiextract --directory "$WINEPREFIX/drive_c/windows/syswow64" /tmp/cache/winetricks/vcrun2022/vc_redist.x86.msi

    # 2. Apply VC++ 2022 DLL overrides manually using 64-bit reg.exe
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "concrt140" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "msvcp140" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "msvcp140_1" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "msvcp140_2" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "msvcp140_atomic_wait" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "msvcp140_codecvt_ids" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "vcamp140" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "vccorlib140" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "vcomp140" /t REG_SZ /d "native,builtin" /f
    ${lib.getExe wine} reg add "HKCU\\Software\\Wine\\DllOverrides" /v "vcruntime140" /t REG_SZ /d "native,builtin" /f

    # 3. Set Windows version to Windows 11
    ${lib.getExe wine} winecfg -v win11

    # 4. Skip .NET installation. 
    # The .exe installers fail in the sandbox, but Wine's built-in Mono handles Affinity fine.

    ${lib.getExe wineserver} -w
  ''
