nix-build ./nixos -A config.system.build.sdImage -I nixos-config=./sd-image.nix --max-jobs 1
