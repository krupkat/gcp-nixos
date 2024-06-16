{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.krupkat.inadyn;
in
{
  options.services.krupkat.inadyn = {
    enable = mkEnableOption (mdDoc "inadyn service");

    package = mkOption {
      type = types.package;
      default = pkgs.inadyn;
      defaultText = literalExpression "pkgs.inadyn";
      description = mdDoc ''
        The inadyn package that should be used.
      '';
    };

    period = mkOption {
      type = types.str;
      default = "60m";
      description = mdDoc ''
        How often to run the service.
      '';
    };

    domains = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = mdDoc ''
        Domains to keep dns synced.
      '';
    };
  };

  config = mkIf cfg.enable {
    sops.templates."inadyn.conf".content =
      let
        quote = (x: "\"" + x + "\"");
        hostnames = concatMapStringsSep ", " (x: quote x) cfg.domains;
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

    systemd.timers.inadyn = {
      description = "Sync inadyn every hour";
      wantedBy = [ "default.target" ];
      timerConfig = {
        OnBootSec = "2m";
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
        LoadCredential = "inadyn.conf:${config.sops.templates."inadyn.conf".path}";
        CacheDirectory = "inadyn";
        ExecStart = ''
          ${cfg.package}/bin/inadyn \
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
