{
  lib,
  stdenv,
  fetchurl,
  fetchzip,
  autoPatchelfHook,
  installShellFiles,
  cpio,
  xar,
  versionCheckHook,
  channel ? "stable",
}:

let
  inherit (stdenv.hostPlatform) system;
  channelSources =
    (builtins.fromJSON (builtins.readFile ./sources.json)).${channel}
      or (throw "unsupported channel ${channel}");
  inherit (channelSources) version hashes;
  fetch =
    srcPlatform: hash: extension:
    let
      args = {
        url = "https://cache.agilebits.com/dist/1P/op2/pkg/v${version}/op_${srcPlatform}_v${version}.${extension}";
        inherit hash;
      }
      // lib.optionalAttrs (extension == "zip") { stripRoot = false; };
    in
    if extension == "zip" then fetchzip args else fetchurl args;

  pname = "1password-cli";
  sources = {
    aarch64-linux = fetch "linux_arm64" hashes.linux_arm64 "zip";
    i686-linux = fetch "linux_386" hashes.linux_386 "zip";
    x86_64-linux = fetch "linux_amd64" hashes.linux_amd64 "zip";
    aarch64-darwin = fetch "apple_universal" hashes.apple_universal "pkg";
  };
  platforms = builtins.attrNames sources;
  mainProgram = "op";
in

stdenv.mkDerivation {
  inherit pname version;
  src =
    if (builtins.elem system platforms) then
      sources.${system}
    else
      throw "Source for 1password-cli is not available for ${system}";

  nativeBuildInputs = [
    installShellFiles
    versionCheckHook
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    xar
    cpio
  ];

  unpackPhase = lib.optionalString stdenv.hostPlatform.isDarwin ''
    xar -xf $src
    zcat op.pkg/Payload | cpio -i
  '';

  installPhase = ''
    runHook preInstall
    install -D op $out/bin/op
    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    HOME=$TMPDIR
    installShellCompletion --cmd op \
      --bash <($out/bin/op completion bash) \
      --fish <($out/bin/op completion fish) \
      --zsh <($out/bin/op completion zsh)
  '';

  dontStrip = stdenv.hostPlatform.isDarwin;

  doInstallCheck = true;

  versionCheckProgram = "${placeholder "out"}/bin/op";

  passthru = {
    updateScript = ./update.sh;
  };

  meta = {
    description = "1Password command-line tool";
    homepage = "https://developer.1password.com/docs/cli/";
    downloadPage = "https://app-updates.agilebits.com/product_history/CLI2";
    maintainers = with lib.maintainers; [
      joelburget
      khaneliman
      savtrip
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    inherit mainProgram platforms;
  };
}
