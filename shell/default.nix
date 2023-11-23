{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {

  buildInputs = with pkgs; [
    google-cloud-sdk
  ];

  shellHook = ''
    export PROJECT_ID=authentic-scout-405520
    export BUCKET_NAME=krupkat_nix_gce
  '';
}
