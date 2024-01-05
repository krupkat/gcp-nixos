{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix>
    <sops-nix/modules/sops>
    ./inadyn.nix
    ./sops.nix
    ./vouch.nix
    ./flatnotes.nix
  ];

  # extra user needed for remote nixos-rebuild support:
  nix.settings.trusted-users = [ "root" "tom" ];

  environment.enableAllTerminfo = true;

  environment.systemPackages = with pkgs; [
    git
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
    credentialsFile = config.sops.templates."websupport_dns.conf".path;
    dnsPropagationCheck = true;
    reloadServices = [
      "node-red.service"
      "mosquitto.service"
      "vouch-proxy.service"
    ];
  };

  services.node-red =
    let
      certDir = config.security.acme.certs."tomaskrupka.cz".directory;
    in
    {
      enable = true;
      port = 1880;
      configFile = pkgs.substituteAll { src = ./templates/node-red-settings.js; cert_dir = certDir; };
    };

  systemd.services.node-red.path = with pkgs; [ nodePackages.npm nodePackages.nodejs bash ];
  systemd.services.node-red.serviceConfig.ExecStartPre =
    "${pkgs.nodePackages.npm}/bin/npm install --prefix ${config.services.node-red.userDir} " +
    "@flowfuse/node-red-dashboard@^0.11.0";

  # switch to LoadCredentials:
  users.users.node-red.extraGroups = [ "acme" ];
  users.users.nginx.extraGroups = [ "acme" "github-actions" ];
  users.users.mosquitto.extraGroups = [ "acme" ];
  users.users.vouch-proxy.extraGroups = [ "acme" ];

  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;

    virtualHosts =
      let
        SSL = {
          useACMEHost = "tomaskrupka.cz";
          forceSSL = true;
        };
        Vouch = {
          extraConfig = ''
            auth_request /validate;
            error_page 401 = @error401;
          '';
          locations."/validate" = {
            proxyPass = "https://127.0.0.1:9090/validate";

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
            302 https://vouch.tomaskrupka.cz/login?url=$scheme://$http_host$request_uri&vouch-failcount=$auth_resp_failcount&X-Vouch-Token=$auth_resp_jwt&error=$auth_resp_err
          '';

          locations."/logout".proxyPass = ''
            https://127.0.0.1:9090/logout
          '';
        };
      in
      {
        "tomaskrupka.cz" = (SSL // {
          locations."/".root = "${config.users.users.github-actions.home}/www";
        });

        "www.tomaskrupka.cz" = (SSL // {
          globalRedirect = "tomaskrupka.cz";
        });

        "node-red.tomaskrupka.cz" = lib.mkMerge [
          SSL
          Vouch
          {
            locations."/" = {
              proxyPass = "https://127.0.0.1:1880/";
              proxyWebsockets = true;

              extraConfig = ''
                auth_request_set $auth_resp_x_vouch_user $upstream_http_x_vouch_user;
                proxy_set_header X-Vouch-User $auth_resp_x_vouch_user;
              '';
            };
          }
        ];

        "notes.tomaskrupka.cz" = lib.mkMerge [
          SSL
          Vouch
          {
            locations."/" = {
              proxyPass = "http://127.0.0.1:8080/";
              proxyWebsockets = true;

              extraConfig = ''
                auth_request_set $auth_resp_x_vouch_user $upstream_http_x_vouch_user;
                proxy_set_header X-Vouch-User $auth_resp_x_vouch_user;
              '';
            };
          }
        ];

        "vouch.tomaskrupka.cz" = (SSL // {
          locations."/" = {
            proxyPass = "https://127.0.0.1:9090";
          };
        });
      };
  };

  systemd.services.nginx.serviceConfig.ProtectHome = "read-only";

  services.mosquitto =
    let
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

  services.inadyn = {
    enable = true;
    configurationTemplate = config.sops.templates."inadyn.conf".path;
  };

  services.vouch-proxy = {
    enable = true;
    configurationTemplate = config.sops.templates."vouch.yaml".path;
  };

  services.flatnotes.enable = true;

  services.restic.backups = {
    gcs = {
      user = config.users.users.backup.name;
      repository = "gs:krupkat_backup_cloud:/e2_micro";
      initialize = true;
      passwordFile = config.sops.secrets."restic/backup_password".path;
      paths = [
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

  users.groups.github-actions = { };
  users.users.github-actions = {
    description = "Github Actions deployments";
    group = config.users.groups.github-actions.name;
    homeMode = "0750";
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFa5xTjWp9+btqQ0hkJiU3gys0xD3/uCXK48ZbzlMvjL github-actions@tomaskrupka.cz"
    ];
  };

  users.groups.backup = { };
  users.users.backup = {
    isSystemUser = true;
    group = config.users.groups.backup.name;
  };

  system.stateVersion = "23.11";
}
