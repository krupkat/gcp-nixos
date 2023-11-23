{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix>
    <sops-nix/modules/sops>
  ];

  nix.settings.trusted-users = [ "root" "tom" ];

  environment.enableAllTerminfo = true;

  environment.systemPackages = with pkgs; [
    inadyn
    screen
    vim
    wget
  ];

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "tomas@krupkat.cz";
  security.acme.certs."tomaskrupka.cz" = {
    domain = "*.tomaskrupka.cz";
    extraDomainNames = [
      "tomaskrupka.cz"
    ];
    dnsProvider = "websupport";
    credentialsFile = "/var/lib/secrets/certs.secret";
    dnsPropagationCheck = true;
    reloadServices = [
      "node-red.service"
      "mosquitto.service"
    ];
  };

  services.node-red = {
    enable = true;
    port = 1880;
    configFile = "/var/lib/node-red/settings.js";
  };

  # systemd.services.node-red.path = with pkgs; [ nodePackages.npm nodejs_18 bash ];
  #systemd.services.node-red.serviceConfig.ExecStartPre = lib.concatMapStrings (module:
  #  "${pkgs.nodePackages.npm}/bin/npm install --prefix ${config.services.node-red.userDir} " + module
  #) [
  #  "node-red-auth-github @flowfuse/node-red-dashboard"
  #];

  # switch to LoadCredentials:
  users.users.node-red.extraGroups = [ "acme" ];
  users.users.nginx.extraGroups = [ "acme" ];
  users.users.mosquitto.extraGroups = [ "acme" ];

  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;

    virtualHosts = let
      SSL = {
        useACMEHost = "tomaskrupka.cz";
        forceSSL = true;
      };
    in {
      "tomaskrupka.cz" = (SSL // {
        locations."/".root = "/var/www";

        serverAliases = [
          "www.tomaskrupka.cz"
        ];
      });

      "node-red.tomaskrupka.cz" = (SSL // {
        locations."/".proxyPass = "https://127.0.0.1:1880/";
        locations."/".proxyWebsockets = true;
      }); 
    };
  };

  services.mosquitto = let
    certDir = config.security.acme.certs."tomaskrupka.cz".directory;
  in 
  {
    enable = true;
    listeners = [
      {
        users.red = {
          acl = [
            "readwrite #"
          ];
          passwordFile = config.sops.secrets."mosquitto/red".path;
        };
        port = 1883;
      }
      {
        users.tiny = {
          acl = [
            "readwrite #"
          ];
          passwordFile = config.sops.secrets."mosquitto/tiny".path;
        };
        settings = {
          protocol = "mqtt";
          require_certificate = false;
          keyfile = certDir + "/key.pem";
          certfile = certDir + "/cert.pem";
          cafile = certDir + "/chain.pem";
        };
        port = 8883;
      }
    ];
  };

  sops = {
    defaultSopsFile = ./secrets/gcp-instance.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "websupport/dns/api_key" = {};
      "websupport/dns/secret" = {};

      "websupport/dyn_dns/api_key" = {};
      "websupport/dyn_dns/secret" = {};

      "github/oauth/client_id" = {};
      "github/oauth/secret" = {};

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
    };

    templates = {

    };
  };

  system.stateVersion = "23.05";
}
