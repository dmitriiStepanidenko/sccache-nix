{
  lib,
  stdenvNoCC,
  fetchzip,
  autoPatchelfHook,
  glibc,
  gcc-unwrapped,
}:
stdenvNoCC.mkDerivation rec {
  pname = "sccache-dist";
  name = "${pname}-${version}";
  version = "0.10.0";
  src = fetchzip {
    hash = "sha256-1D5uVsbmJcpr4rM8R8qXMdeU6xaec9w0QnJxNe8tAA8=";
    url = "https://github.com/mozilla/sccache/releases/download/v${version}/sccache-dist-v${version}-x86_64-unknown-linux-musl.tar.gz";
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
    install -m755 sccache-dist-v${version}-x86_64-unknown-linux-musl/sccache-dist $out/bin
    runHook postInstall
  '';

  meta = with lib; {
    description = "Sccache dist";
    platforms = platforms.gnu;
  };
}
