{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  nix-update-script,
}:
# Adapted from nixpkgs (pkgs/by-name/fi/firecrawl-cli), tracking upstream releases.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "firecrawl-cli";
  version = "1.30.0";

  outputs = [
    "out"
    "skills"
  ];

  src = fetchFromGitHub {
    owner = "firecrawl";
    repo = "cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-WIICx/oyhRD76kI6uUiSIwpVs1YH6HBPMGWuVcxVr54=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-Sh4KRAB4UhEZzj4nMJ9kUMd/gmNV0rMgtcsbgKkPzCw=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpmConfigHook
    pnpm_10
  ];

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/firecrawl-cli

    # `pnpm build` doesn't bundle dependencies, so keep a pruned node_modules
    CI=true pnpm --ignore-scripts --prod prune
    find -type f \( -name "*.ts" -o -name "*.map" \) -delete
    find node_modules -xtype l -delete  # https://github.com/pnpm/pnpm/issues/3645

    cp -r dist node_modules package.json $out/lib/firecrawl-cli

    cp -r skills $skills
    ln -s $skills $out/lib/firecrawl-cli/skills

    # Entry point comes from package.json "bin" so it survives upstream renames
    # (index.js -> launcher.js happened in 1.27+).
    entry=$(node -p 'Object.values(require("./package.json").bin ?? {})[0] ?? "dist/index.js"')
    makeWrapper ${lib.getExe nodejs} $out/bin/firecrawl \
      --add-flags "$out/lib/firecrawl-cli/$entry" \
      --set-default FIRECRAWL_NO_TELEMETRY 1

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {};

  meta = {
    description = "CLI and Agent Skill for Firecrawl: scrape, search, and browse from the terminal";
    homepage = "https://github.com/firecrawl/cli";
    changelog = "https://github.com/firecrawl/cli/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    mainProgram = "firecrawl";
    platforms = lib.platforms.all;
  };
})
