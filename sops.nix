{ config, lib, ... }:

let
  certDir = config.security.acme.certs."tomaskrupka.cz".directory;
in
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

      "websupport/dyn_dns/api_key" = { };
      "websupport/dyn_dns/secret" = { };

      "google/oauth/client_id" = {
        restartUnits = [ "vouch-proxy.service" ];
      };

      "google/oauth/secret" = {
        restartUnits = [ "vouch-proxy.service" ];
      };

      "mosquitto/red" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        reloadUnits = [ "mosquitto.service" ];
      };

      "mosquitto/tiny" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        reloadUnits = [ "mosquitto.service" ];
      };

      "vouch/jwt_secret" = { };

      "restic/backup_password" = {
        owner = config.users.users.backup.name;
      };

      "restic/gcs_keys" = {
        format = "binary";
        sopsFile = ./secrets/authentic-scout-405520-ae7f408dd47d.json;
        owner = config.users.users.backup.name;
      };
    };

    templates = {
      "vouch.yaml".content = ''
        vouch:
          port: 9090
          domains:
            - tomaskrupka.cz
          cookie:
            domain: tomaskrupka.cz
          whitelist:
            - tomas@krupkat.cz
          tls:
            cert: ${certDir}/cert.pem
            key: ${certDir}/key.pem
          jwt:
            secret: ${config.sops.placeholder."vouch/jwt_secret"}
        oauth:
          provider: google
          client_id: ${config.sops.placeholder."google/oauth/client_id"}
          client_secret: ${config.sops.placeholder."google/oauth/secret"}
          callback_urls:
            - https://vouch.tomaskrupka.cz/auth
          scopes:
            - email
      '';

      "websupport_dns.conf".content = ''
        WEBSUPPORT_API_KEY='${config.sops.placeholder."websupport/dns/api_key"}'
        WEBSUPPORT_SECRET='${config.sops.placeholder."websupport/dns/secret"}'
      '';

      "inadyn.conf".content =
        let
          quote = (x: "\"" + x + "\"");
          hostname = "tomaskrupka.cz";
          hostnames = quote hostname + (lib.concatMapStrings (x: ", " + quote (x + "." + hostname))
            [ "www" "node-red" "vouch" "home" "notes" ]);
        in
        ''
          # In-A-Dyn v2.0 configuration file format
          period          = 600
          user-agent      = Mozilla/5.0

          custom websupport {
              ssl            = true
              username       = ${config.sops.placeholder."websupport/dyn_dns/api_key"}
              password       = ${config.sops.placeholder."websupport/dyn_dns/secret"}
              checkip-server = ifconfig.me
              checkip-path   = /ip
              checkip-ssl    = true
              ddns-server    = dyndns.websupport.cz
              ddns-path      = "/nic/update?hostname=%h&myip=%i"
              hostname       = { ${hostnames} }
          }
        '';
    };
  };
}
