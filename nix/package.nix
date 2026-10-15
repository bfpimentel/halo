# The prebuilt universal release zip (see scripts/package.sh), wrapped to use nixpkgs' esbuild.
{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  esbuild,
  release,
}:

stdenvNoCC.mkDerivation {
  pname = "halo";
  inherit (release) version;

  src = fetchzip {
    url = release.url or "https://github.com/bfpimentel/halo/releases/download/v${release.version}/halo-${release.version}-macos.zip";
    hash = if release.hash == "" then lib.fakeHash else release.hash;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;
  # Stripping would invalidate the linker's ad-hoc signature, which Apple Silicon requires to run the binary.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R bin share $out/
    wrapProgram $out/bin/halo \
      --set-default HALO_ESBUILD ${lib.getExe esbuild} \
      --set-default HALO_RUNTIME $out/share/halo/runtime
    runHook postInstall
  '';

  meta = {
    description = "Widget runtime for macOS: bars, panels and HUDs written in TSX";
    homepage = "https://github.com/bfpimentel/halo";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.darwin;
    mainProgram = "halo";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
