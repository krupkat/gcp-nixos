{ config, lib, ... }:
let
  serviceName = name: assert config.systemd.services ? "${name}" ; "${name}.service";
  acmeService = serviceName "acme-tomaskrupka.cz";
  inadynService = serviceName "inadyn";
  vouchService = serviceName "vouch-proxy";
  mosquittoService = serviceName "mosquitto";
  resticService = serviceName "restic-backups-gcs";
in
{
  config.sops = {
    defaultSopsFile = ./secrets/gcp-instance.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "websupport/dns/api_key" = {
        reloadUnits = [ acmeService ];
      };
      "websupport/dns/secret" = {
        reloadUnits = [ acmeService ];
      };

      "websupport/dyn_dns/api_key" = {
        reloadUnits = [ inadynService ];
      };
      "websupport/dyn_dns/secret" = {
        reloadUnits = [ inadynService ];
      };

      "google/oauth/client_id" = {
        restartUnits = [ vouchService ];
      };
      "google/oauth/secret" = {
        restartUnits = [ vouchService ];
      };
      "vouch/jwt_secret" = {
        restartUnits = [ vouchService ];
      };

      "mosquitto/red" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        restartUnits = [ mosquittoService ];
      };
      "mosquitto/tiny" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        restartUnits = [ mosquittoService ];
      };

      "restic/backup_password" = {
        owner = config.users.users.backup.name;
        group = config.users.users.backup.group;
        reloadUnits = [ resticService ];
      };
      "restic/gcs_keys" = {
        format = "binary";
        sopsFile = ./secrets/authentic-scout-405520-a114456c68f1.json;
        owner = config.users.users.backup.name;
        group = config.users.users.backup.group;
        reloadUnits = [ resticService ];
      };
    };
  };
}
