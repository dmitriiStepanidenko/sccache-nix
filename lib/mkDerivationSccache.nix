{
  lib,
  stdenvNoCC,
  fetchzip,
  autoPatchelfHook,
  glibc,
  gcc-unwrapped,
}:
stdenvNoCC.mkDerivation rec {
  pname = "sccache";
  name = "${pname}-${version}";
  version = "0.10.0";
  src = fetchzip {
    hash = "sha256-G/haJsKPUsmWmy32c/XNTwI7lz73M0KK7A3ojhQwiG0=";
    url = "https://github.com/mozilla/sccache/releases/download/v${version}/sccache-v${version}-x86_64-unknown-linux-musl.tar.gz";
    stripRoot = false;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    glibc
    gcc-unwrapped
  ];
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 sccache-v${version}-x86_64-unknown-linux-musl/sccache $out/bin
    runHook postInstall
  '';

  meta = with lib; {
    description = "Sccache";
    platforms = platforms.gnu;
  };
}
