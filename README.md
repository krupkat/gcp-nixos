# gcp-nixos

## incremental rebuild

```
nixos-rebuild --target-host tomaskrupka.cz --use-remote-sudo switch -I nixos-config=configuration.nix
```

## new machine setup

Create new machine according to https://nixos.wiki/wiki/Install_NixOS_on_GCE

1. connect to the new instance with Cloud Shell
2. `sudo nano /etc/nixos/configuration.nix`
  a. add: `nix.settings.trusted-users = [ "root" "tom" ];`
  b. `sudo nixos-rebuild switch`
3. Generate sops key for the device
  a. `nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'`
  b. add the result to `.sops.yaml`
4. Rebuild the secrets file
  a. TODO: improve this:
  b. `sops -d secrets/gcp-instance.yaml > secrets/tmp.yaml`
  c. `sops -e secrets/tmp.yaml > secrets/gcp-instance.yaml`
  d. `rm secrets/tmp.yaml`

# encrypt a file verbatim

```
sops --input-type binary -e secrets/tmp.json > secrets/encrypted.json
```