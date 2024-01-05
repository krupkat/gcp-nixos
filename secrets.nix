{ config, lib, ... }:

{
  sops = {
    defaultSopsFile = ./secrets/gcp-instance.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "websupport/dns/api_key" = {
        reloadUnits = [ "acme-tomaskrupka.cz.service" ];
      };
      "websupport/dns/secret" = {
        reloadUnits = [ "acme-tomaskrupka.cz.service" ];
      };

      "websupport/dyn_dns/api_key" = {
        reloadUnits = [ "inadyn.service" ];
      };
      "websupport/dyn_dns/secret" = {
        reloadUnits = [ "inadyn.service" ];
      };

      "google/oauth/client_id" = {
        restartUnits = [ "vouch-proxy.service" ];
      };
      "google/oauth/secret" = {
        restartUnits = [ "vouch-proxy.service" ];
      };
      "vouch/jwt_secret" = {
        restartUnits = [ "vouch-proxy.service" ];
      };

      "mosquitto/red" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        restartUnits = [ "mosquitto.service" ];
      };
      "mosquitto/tiny" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        restartUnits = [ "mosquitto.service" ];
      };

      "restic/backup_password" = {
        owner = config.users.users.backup.name;
        group = config.users.users.backup.group;
        reloadUnits = [ "restic-backups-gcs.service" ];
      };
      "restic/gcs_keys" = {
        format = "binary";
        sopsFile = ./secrets/authentic-scout-405520-ce3e009f013c.json;
        owner = config.users.users.backup.name;
        group = config.users.users.backup.group;
        reloadUnits = [ "restic-backups-gcs.service" ];
      };
    };
  };
}
