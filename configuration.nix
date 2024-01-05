{ config, lib, pkgs, ... }:

let
  domain = "tomaskrupka.cz";
in
{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix>
    <sops-nix/modules/sops>
    ./inadyn.nix
    ./secrets.nix
    ./vouch.nix
    ./flatnotes.nix
  ];

  # extra user needed for remote nixos-rebuild support:
  nix.settings.trusted-users = [ "root" "tom" ];

  environment = {
    enableAllTerminfo = true;
    systemPackages = with pkgs; [
      git
      screen
      vim
      wget
    ];
  };

  sops.templates = {
    "websupport_dns.conf".content = ''
      WEBSUPPORT_API_KEY='${config.sops.placeholder."websupport/dns/api_key"}'
      WEBSUPPORT_SECRET='${config.sops.placeholder."websupport/dns/secret"}'
    '';
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "tomas@krupkat.cz";
    certs."${domain}" = {
      domain = "*.${domain}";
      extraDomainNames = [ domain ];
      dnsProvider = "websupport";
      credentialsFile = config.sops.templates."websupport_dns.conf".path;
      dnsPropagationCheck = true;
      reloadServices = [
        "node-red.service"
        "mosquitto.service"
        "vouch-proxy.service"
      ];
    };
  };

  services = {
    node-red =
      let
        certDir = config.security.acme.certs."${domain}".directory;
      in
      {
        enable = true;
        port = 1880;
        configFile = pkgs.substituteAll { src = ./templates/node-red-settings.js; cert_dir = certDir; };
      };

    nginx = {
      enable = true;

      recommendedGzipSettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;

      virtualHosts =
        let
          vouchPort = toString config.services.vouch-proxy.port;
          flatnotesPort = toString config.services.flatnotes.port;
          nodeRedPort = toString config.services.node-red.port;
          sslConfig = {
            useACMEHost = domain;
            forceSSL = true;
          };
          vouchConfig = {
            extraConfig = ''
              auth_request /validate;
              error_page 401 = @error401;
            '';
            locations."/validate" = {
              proxyPass = "https://127.0.0.1:${vouchPort}/validate";

              extraConfig = ''
                proxy_pass_request_body off;
                proxy_set_header Content-Length "";

                auth_request_set $auth_resp_x_vouch_user $upstream_http_x_vouch_user;

                auth_request_set $auth_resp_jwt $upstream_http_x_vouch_jwt;
                auth_request_set $auth_resp_err $upstream_http_x_vouch_err;
                auth_request_set $auth_resp_failcount $upstream_http_x_vouch_failcount;
              '';
            };
            locations."@error401".return = ''
              302 https://vouch.${domain}/login?url=$scheme://$http_host$request_uri&vouch-failcount=$auth_resp_failcount&X-Vouch-Token=$auth_resp_jwt&error=$auth_resp_err
            '';

            locations."/logout".proxyPass = ''
              https://127.0.0.1:${vouchPort}/logout
            '';
          };
        in
        {
          "${domain}" = (sslConfig // {
            locations."/".root = "${config.users.users.github-actions.home}/www";
          });

          "www.${domain}" = (sslConfig // {
            globalRedirect = domain;
          });

          "node-red.${domain}" = lib.mkMerge [
            sslConfig
            vouchConfig
            {
              locations."/" = {
                proxyPass = "https://127.0.0.1:${nodeRedPort}/";
                proxyWebsockets = true;

                extraConfig = ''
                  auth_request_set $auth_resp_x_vouch_user $upstream_http_x_vouch_user;
                  proxy_set_header X-Vouch-User $auth_resp_x_vouch_user;
                '';
              };
            }
          ];

          "notes.${domain}" = lib.mkMerge [
            sslConfig
            vouchConfig
            {
              locations."/" = {
                proxyPass = "http://127.0.0.1:${flatnotesPort}/";
                proxyWebsockets = true;

                extraConfig = ''
                  auth_request_set $auth_resp_x_vouch_user $upstream_http_x_vouch_user;
                  proxy_set_header X-Vouch-User $auth_resp_x_vouch_user;
                '';
              };
            }
          ];

          "vouch.${domain}" = (sslConfig // {
            locations."/" = {
              proxyPass = "https://127.0.0.1:${vouchPort}";
            };
          });
        };
    };

    mosquitto =
      let
        certDir = config.security.acme.certs."${domain}".directory;
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

    inadyn = {
      enable = true;
      period = "10m";
      hostname = domain;
      subdomains = [ "www" "node-red" "vouch" "home" "notes" ];
    };

    vouch-proxy = {
      enable = true;
      certDir = config.security.acme.certs."${domain}".directory;
      hostname = domain;
      port = 9090;
    };

    flatnotes = {
      enable = true;
      port = 8080;
    };

    restic.backups.gcs = {
      user = config.users.users.backup.name;
      repository = "gs:krupkat_backup_cloud:/e2_micro";
      initialize = true;
      passwordFile = config.sops.secrets."restic/backup_password".path;
      paths = [
        "/home/github-actions/www"
        "/var/lib/node-red"
        "/var/lib/flatnotes"
      ];
      environmentFile = builtins.toFile "restic_gcs_env" ''
        GOOGLE_PROJECT_ID='authentic-scout-405520'
        GOOGLE_APPLICATION_CREDENTIALS='${config.sops.secrets."restic/gcs_keys".path}'
      '';
      extraBackupArgs =
        let
          ignoreFile = builtins.toFile "ignore" ''
            /var/lib/node-red/node-modules
            /var/lib/node-red/.npm
          '';
        in
        [ "--exclude-file=${ignoreFile}" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };

  systemd.services = {
    # this is to give nginx access to /home/github-actions/www
    nginx.serviceConfig.ProtectHome = "read-only";

    # install specific nodejs dependencies to the node-red service
    node-red.path = with pkgs; [ nodePackages.npm nodePackages.nodejs bash ];
    node-red.serviceConfig.ExecStartPre =
      "${pkgs.nodePackages.npm}/bin/npm install --prefix ${config.services.node-red.userDir} " +
      "@flowfuse/node-red-dashboard@^0.11.0";
  };

  users = {
    groups =
      {
        github-actions = { };
        backup = { };
      };

    users = {
      github-actions = {
        description = "Github Actions deployments";
        group = config.users.groups.github-actions.name;
        homeMode = "0750";
        isNormalUser = true;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFa5xTjWp9+btqQ0hkJiU3gys0xD3/uCXK48ZbzlMvjL"
        ];
      };

      backup = {
        isSystemUser = true;
        group = config.users.groups.backup.name;
        extraGroups = [ "github-actions" ];
      };

      # these users need access to ssl certificates
      node-red.extraGroups = [ "acme" ];
      nginx.extraGroups = [ "acme" "github-actions" ]; # + access to /home/github-actions/www
      mosquitto.extraGroups = [ "acme" ];
      vouch-proxy.extraGroups = [ "acme" ];
    };
  };

  system.stateVersion = "23.11";
}
