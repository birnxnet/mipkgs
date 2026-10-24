{
  callPackage,
  # This is only relevant for Linux, so we need to pass it through
  polkitPolicyOwners ? [ ],
}:
callPackage ../_1password-gui/package.nix {
  channel = "beta";
  inherit polkitPolicyOwners;
}
