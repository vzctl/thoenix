{
  inputs,
  self,
  ...
} @ part-inputs: {
  imports = [];

  perSystem = {
    pkgs,
    lib,
    system,
    inputs',
    ...
  }: let
    devTools = with pkgs; [
      # rust tooling
      fenix-toolchain
      bacon
      rustfmt
      cargo-nextest
      # misc
      pkgs.terraform
    ];

    extraNativeBuildInputs = [
      pkgs.pkg-config
      pkgs.openssl
      pkgs.openssl.dev
    ]  ++ lib.optionals pkgs.stdenv.isDarwin [
      pkgs.libiconv
      pkgs.darwin.apple_sdk.frameworks.AppKit
      pkgs.darwin.apple_sdk.frameworks.CoreFoundation
      pkgs.darwin.apple_sdk.frameworks.CoreServices
      pkgs.darwin.apple_sdk.frameworks.Foundation
      pkgs.darwin.apple_sdk.frameworks.Security
    ];

    # allBuildInputs = base: base ++ extraBuildInputs;
    allNativeBuildInputs = base: base ++ extraNativeBuildInputs;

    fenix-channel = inputs'.fenix.packages.latest;
    fenix-toolchain = fenix-channel.withComponents [
      "rustc"
      "cargo"
      "clippy"
      "rust-analysis"
      "rust-src"
      "rustfmt"
      "llvm-tools-preview"
    ];

    craneLib = inputs.crane.lib.${system}.overrideToolchain fenix-toolchain;

    common-build-args = rec {
      src = inputs.nix-filter.lib {
        root = ../.;
        include = [
          "crates"
          "Cargo.toml"
          "Cargo.lock"
        ];
      };

      pname = "thoenix";

      nativeBuildInputs = allNativeBuildInputs [];
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath nativeBuildInputs;
    };
    deps-only = craneLib.buildDepsOnly ({} // common-build-args);

    clippy-check = craneLib.cargoClippy ({
        cargoArtifacts = deps-only;
        cargoClippyExtraArgs = "--all-features -- --deny warnings";
      }
      // common-build-args);

    rust-fmt-check = craneLib.cargoFmt ({
        inherit (common-build-args) src;
      }
      // common-build-args);

    tests-check = craneLib.cargoNextest ({
        cargoArtifacts = deps-only;
        partitions = 1;
        partitionType = "count";
      }
      // common-build-args);

    pre-commit-hooks = inputs.pre-commit-hooks.lib.${system}.run {
      inherit (common-build-args) src;
      hooks = {
        alejandra.enable = true;
        rustfmt.enable = true;
      };
    };

    cli-package = craneLib.buildPackage ({
        pname = "thoenix";
        cargoArtifacts = deps-only;
        cargoExtraArgs = "--bin thoenix";
      }
      // common-build-args);
  in rec {
    devShells.default = pkgs.mkShell rec {
      packages = allNativeBuildInputs [fenix-toolchain] ++ devTools;
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath packages;
      inherit (self.checks.${system}.pre-commit-hooks) shellHook;
    };

    packages = {
      inherit fenix-toolchain;
      default = packages.cli;
      cli = cli-package;
    };

    apps = {
      cli = {
        type = "app";
        program = "${self.packages.${system}.cli}/bin/thoenix";
      };
      default = apps.cli;
    };

    checks = {
      inherit pre-commit-hooks;
      clippy = clippy-check;
      tests = tests-check;
      rust-fmt = rust-fmt-check;
    };
  };
}
