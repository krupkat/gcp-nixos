{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.inadyn;
  pkg = getBin cfg.package;
in
{
  options.services.inadyn = {
    enable = mkEnableOption (lib.mdDoc "inadyn service");

    package = mkOption {
      type = types.package;
      default = pkgs.inadyn;
      defaultText = literalExpression "pkgs.inadyn";
      description = lib.mdDoc ''
        The inadyn package that should be used.
      '';
    };

    configurationTemplate = mkOption {
      type = types.singleLineStr;
      description = lib.mdDoc ''
        Path to inadyn configuration sops-nix template
        ([documentation](https://github.com/troglobit/inadyn/blob/master/README.md#configuration))
      '';
    };

    period = mkOption {
      type = types.str;
      default = "60m";
      description = lib.mdDoc ''
        How often to run the service.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.timers.inadyn = {
      description = "Sync inadyn every hour";
      wantedBy = [ "default.target" ];
      timerConfig = {
        OnBootSec = cfg.period;
        OnUnitActiveSec = cfg.period;
      };
    };

    systemd.services.inadyn = {
      description = "Syncs home IP to dynamic DNS.";
      requires = [ "network-online.target" ];
      serviceConfig = {
        DynamicUser = true;
        Type = "oneshot";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateUsers = true;
        PrivateTmp = true;
        LoadCredential = "inadyn.conf:${cfg.configurationTemplate}";
        CacheDirectory = "inadyn";
        ExecStart = ''
          ${pkg}/bin/inadyn \
            --foreground \
            --syslog \
            --once \
            --cache-dir ''${CACHE_DIRECTORY} \
            --config ''${CREDENTIALS_DIRECTORY}/inadyn.conf
        '';
      };
    };
  };
}
