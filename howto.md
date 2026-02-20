# Howto

## Free tier

Stick to the [free tier](https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits) Google Cloud limits for a completely free instance. Since the machine only has 1GB ram, it can be a challenge to rebuild a new confiuration there, in that case use remote rebuild:

## Remote rebuild

```
nixos-rebuild --target-host tomaskrupka --ask-sudo-password switch -I nixos-config=configuration.nix --no-flake
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

## Patch nixos vm build

```diff
diff --git a/nixos/maintainers/scripts/gce/create-gce.sh b/nixos/maintainers/scripts/gce/create-gce.sh
index 0eec4d041108..ea9ae4332313 100755
--- a/nixos/maintainers/scripts/gce/create-gce.sh
+++ b/nixos/maintainers/scripts/gce/create-gce.sh
@@ -7,9 +7,9 @@ BUCKET_NAME="${BUCKET_NAME:-nixos-cloud-images}"
 TIMESTAMP="$(date +%Y%m%d%H%M)"
 export TIMESTAMP
 
-nix-build '<nixpkgs/nixos/lib/eval-config.nix>' \
+nix-build './nixos/lib/eval-config.nix' \
    -A config.system.build.googleComputeImage \
-   --arg modules "[ <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix> ]" \
+   --arg modules "[ ./nixos/modules/virtualisation/google-compute-image.nix ]" \
    --argstr system x86_64-linux \
    -o gce \
    -j 10
diff --git a/nixos/modules/virtualisation/google-compute-config.nix b/nixos/modules/virtualisation/google-compute-config.nix
index 8f9e2b4f4075..dc44c7eecaac 100644
--- a/nixos/modules/virtualisation/google-compute-config.nix
+++ b/nixos/modules/virtualisation/google-compute-config.nix
@@ -55,7 +55,7 @@ in
 
   # enable OS Login. This also requires setting enable-oslogin=TRUE metadata on
   # instance or project level
-  security.googleOsLogin.enable = true;
+  security.googleOsLogin.enable = false;
 
   # Use GCE udev rules for dynamic disk volumes
   services.udev.packages = [ pkgs.google-guest-configs ];
@@ -141,4 +141,16 @@ in
     # We set up network interfaces declaratively.
     setup = false
   '';
+
+  users.users.tom = {
+    isNormalUser = true;
+    extraGroups = [ "wheel" ];
+    initialPassword = "123456";
+    openssh.authorizedKeys.keys = [
+      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDq+98u++bivMPalMrNLKAdNE+gyYOzZrrQYBCpIw3Nu"
+    ];
+  };
+
+  nix.settings.trusted-users = [ "root" "tom" ];
+  nix.settings.require-sigs = false;
 }
```