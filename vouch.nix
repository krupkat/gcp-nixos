{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.vouch-proxy;
in
{
  options.services.vouch-proxy = {
    enable = mkEnableOption (lib.mdDoc "vouch-proxy service");

    package = mkOption {
      type = types.package;
      default = pkgs.vouch-proxy;
      defaultText = literalExpression "pkgs.vouch-proxy";
      description = lib.mdDoc ''
        The vouch-proxy package that should be used.
      '';
    };

    certDir = mkOption {
      type = types.str;
      description = lib.mdDoc ''
        Directory with ssl certificates for the domain.
      '';
    };
  };

  config = mkIf cfg.enable {
    sops.templates."vouch.yaml".content = ''
      vouch:
        port: 9090
        domains:
          - tomaskrupka.cz
        cookie:
          domain: tomaskrupka.cz
        whitelist:
          - tomas@krupkat.cz
        tls:
          cert: ${cfg.certDir}/cert.pem
          key: ${cfg.certDir}/key.pem
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

    systemd.services.vouch-proxy = {
      description = "Vouch Proxy";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = 60;
      };
      serviceConfig = {
        User = "vouch-proxy";
        WorkingDirectory = "/var/lib/vouch-proxy";
        StateDirectory = "vouch-proxy";
        LoadCredential = "config.yaml:${config.sops.templates."vouch.yaml".path}";
        ExecStart = ''
          ${cfg.package}/bin/vouch-proxy -config ''${CREDENTIALS_DIRECTORY}/config.yaml
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    users.users.vouch-proxy = {
      isSystemUser = true;
      group = "vouch-proxy";
    };

    users.groups.vouch-proxy = { };
  };
}
