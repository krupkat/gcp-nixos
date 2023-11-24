{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix>
    <sops-nix/modules/sops>
    ./inadyn.nix
    ./sops.nix
    ./vouch.nix
  ];

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
    ];
  };

  services.node-red = {
    enable = true;
    port = 1880;
    configFile = "/var/lib/node-red/settings.js";
  };

  systemd.services.node-red.path = with pkgs; [ nodePackages.npm nodejs_18 bash ];
  systemd.services.node-red.serviceConfig.ExecStartPre =
    "${pkgs.nodePackages.npm}/bin/npm install --prefix ${config.services.node-red.userDir} " +
    "node-red-auth-github @flowfuse/node-red-dashboard";

  # switch to LoadCredentials:
  users.users.node-red.extraGroups = [ "acme" ];
  users.users.nginx.extraGroups = [ "acme" ];
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
      in
      {
        "tomaskrupka.cz" = (SSL // {
          locations."/".root = "/var/www";

          serverAliases = [
            "www.tomaskrupka.cz"
          ];
        });

        "node-red.tomaskrupka.cz" = (SSL // {
          extraConfig = ''
            auth_request /validate;
            error_page 401 = @error401;
          '';

          locations."/" = {
            proxyPass = "https://127.0.0.1:1880/";
            proxyWebsockets = true;

            extraConfig = ''
              auth_request_set $auth_resp_x_vouch_user $upstream_http_x_vouch_user;
              proxy_set_header X-Vouch-User $auth_resp_x_vouch_user;
            '';
          };

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
        });

        "vouch.tomaskrupka.cz" = (SSL // {
          locations."/" = {
            proxyPass = "https://127.0.0.1:9090";
          };
        });
      };
  };

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

  system.stateVersion = "23.05";
}
