# Howto

## Free tier

Stick to the [free tier](https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits) Google Cloud limits for a completely free instance. Since the machine only has 1GB ram, it can be a challenge to rebuild a new confiuration there, in that case use remote rebuild:

## Remote rebuild

```
nixos-rebuild --target-host tomaskrupka.cz --use-remote-sudo switch -I nixos-config=configuration.nix --no-flake
```

## New machine setup

Create new machine according to https://wiki.nixos.org/wiki/Install_NixOS_on_GCE

1. Connect to the new instance with Cloud Shell
2. `sudo nano /etc/nixos/configuration.nix`
    1. add: `nix.settings.trusted-users = [ "root" "tom" ];`
    2. add: `nix.settings.require-sigs = false;`
    3. `sudo nixos-rebuild switch`
3. Generate sops key for the device
    1. `nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'`
    2. add the result to `.sops.yaml`
4. Rebuild the secrets file
    1. TODO: improve this:
    2. `sops -d secrets/gcp-instance.yaml > secrets/tmp.yaml`
    3. `sops -e secrets/tmp.yaml > secrets/gcp-instance.yaml`
    4. `rm secrets/tmp.yaml`

## Encrypt a file verbatim

```
sops --input-type binary -e secrets/tmp.json > secrets/encrypted.json
```
