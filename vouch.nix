{ config, pkgs, lib, ... }: 

with lib;

let
  cfg = config.services.vouch-proxy;
  pkg = getBin cfg.package;
  configYaml = (pkgs.formats.yaml {}).generate "vouch-proxy-config.yml" cfg.configuration;
  defaultConfig = {};
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

    configuration = mkOption {
      type = types.attrsOf types.unspecified;
      default = defaultConfig;
      example = literalExpression "{}";
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
        ExecStart = "${pkg}/bin/vouch-proxy -config ${configYaml}";
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
