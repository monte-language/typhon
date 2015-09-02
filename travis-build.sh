#! /bin/bash
set -e

export NIX_CURL_FLAGS=-sS

echo "=== Installing Nix..."
# Install Nix
bash <(curl -sS https://nixos.org/nix/install)
source $HOME/.nix-profile/etc/profile.d/nix.sh

# Make sure we can use hydra's binary cache
sudo mkdir /etc/nix
sudo tee /etc/nix/nix.conf <<EOF >/dev/null
binary-caches = http://cache.nixos.org http://hydra.nixos.org http://selina.inze.house:3000/project/typhon/channel/latest
trusted-binary-caches = http://hydra.nixos.org
build-max-jobs = 4
EOF
source $HOME/.nix-profile/etc/profile.d/nix.sh
nix-env -iA latest.typhonVm
nix-build default.nix -A mast
