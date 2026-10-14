{
  fetchurl,
  lib,
  runCommand,
}:
let
  paths = {
    "Microsoft.WebView2.FixedVersionRuntime.133.0.3065.92.x64.cab" = fetchurl {
      url = "https://github.com/westinyang/WebView2RuntimeArchive/releases/download/133.0.3065.92/Microsoft.WebView2.FixedVersionRuntime.133.0.3065.92.x64.cab";
      hash = "sha256-Li694zL9MZ+J92lihXTpQjChxxWpKKW4Ru7sAS6BEkI=";
    };
  };
in
runCommand "dependencies" { } ''
  mkdir -p $out

  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: content: ''
      ln -s ${content} $out/${name}
    '') paths
  )}
''
