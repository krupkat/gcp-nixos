{ config, pkgs, lib, ... }: 

with lib;

let
  cfg = config.services.vouch-proxy;
  pkg = getBin cfg.package;
in {
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

    configurationTemplate = mkOption {
      type = types.singleLineStr;
      description = lib.mdDoc ''
        vouch-proxy configuration
        ([documentation](https://github.com/vouch/vouch-proxy))
        as a Nix attribute set.
      '';
    };
  };

  config = mkIf cfg.enable {
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
        LoadCredential = "config.yaml:${cfg.configurationTemplate}";
        ExecStart = ''
          ${pkg}/bin/vouch-proxy -config ''${CREDENTIALS_DIRECTORY}/config.yaml
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    users.users.vouch-proxy = {
      isSystemUser = true;
      group = "vouch-proxy";
    };

    users.groups.vouch-proxy = {};
  };
}
