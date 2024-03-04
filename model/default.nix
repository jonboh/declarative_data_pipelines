{ pkgs ? import <nixpkgs> { } }:
let
  rustPlatform = pkgs.rustPlatform;
  src = pkgs.lib.cleanSource ./.;
  rustPackage = rustPlatform.buildRustPackage rec {
    pname = "model";
    version = "0.1.0";
    # Provide the source of the Rust project.
    inherit src;
    # Specify the Cargo.lock and Cargo.toml files.
    cargoLock = { lockFile = ./Cargo.lock; };
    cargoToml = ./Cargo.toml;

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      zlib
      cyrus_sasl
      rustPlatform.cargoSetupHook
    ];
    buildInputs = with pkgs; [ openssl ];
    doCheck = false;
    env = { OPENSSL_NO_VENDOR = true; };
    meta = with pkgs.lib; {
      description = "Mock kafka client acting as a model";
      homepage = "https://github.com/declarative_data_pipelines";
      license = licenses.mit;
      maintainers = with maintainers; [ jonboh ];
    };
  };
in rustPackage
