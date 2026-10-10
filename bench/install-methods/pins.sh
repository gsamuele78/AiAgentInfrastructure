# shellcheck shell=bash
# shellcheck disable=SC2034  # letti indirettamente da pin() e dagli adattatori
# Pin di prova di P2b (PREREG.md). Non sono i pin dello stack: servono due
# versioni vicine per misurare aggiornamento e rollback.
NODE_A=24.20.0;     NODE_B=24.21.0
OPENCODE_A=1.18.33; OPENCODE_B=1.18.34
GRAPHIFY_A=0.9.73;  GRAPHIFY_B=0.9.74
MISE_VERSION=2026.10.0
# nix non sceglie la versione del singolo pacchetto: si pinna una release di
# nixpkgs (URL immutabile). A = 26.05 stabile, B = unstable.
NIXPKGS_A=https://releases.nixos.org/nixos/26.05/nixos-26.05.11576.7c8764b7c7b0/nixexprs.tar.xz
NIXPKGS_B=https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1088030.8edc0c72e3a3/nixexprs.tar.xz
DISTROBOX_IMAGE=docker.io/library/debian:13

# pin <tool> <A|B>
pin(){ local v="${1^^}_$2"; echo "${!v}"; }
