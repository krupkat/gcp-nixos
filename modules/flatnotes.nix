{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.flatnotes;
in
{
  options.services.flatnotes = {
    enable = mkEnableOption (mdDoc "flatnotes service");

    port = mkOption {
      type = types.port;
      default = 8080;
      description = mdDoc "Listening port.";
    };

    userDir = mkOption {
      type = types.path;
      default = "/var/lib/flatnotes";
      description = lib.mdDoc ''
        The directory to store all user data.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.flatnotes =
      let
        uid = config.users.users.flatnotes.uid;
        gid = config.users.groups.flatnotes.gid;
        podman = pkgs.podman.override {
          extraPackages = [
            "/run/wrappers" # setuid shadow
          ];
        };
        ExecStartPreScript = pkgs.writeShellApplication {
          name = "exec-start-pre";
          runtimeInputs = [ podman ];
          text = ''
            podman rm -f flatnotes || true
          '';
        };
        ExecStartScript = pkgs.writeShellApplication {
          name = "exec-start";
          runtimeInputs = [ podman ];
          text = ''
            set -e
            exec podman run \
              --rm \
              --name='flatnotes' \
              --log-driver=journald \
              --cidfile=/run/flatnotes/podman-'flatnotes'.ctr-id \
              --cgroups=no-conmon \
              --sdnotify=conmon \
              --user='${toString uid}:${toString gid}' \
              --userns='keep-id' \
              -d \
              --replace \
              -e 'FLATNOTES_AUTH_TYPE'='none' \
              -p '127.0.0.1:${toString cfg.port}:8080' \
              -v '${cfg.userDir}:/data' \
              dullage/flatnotes:latest
          '';
        };
        ExecStopScript = pkgs.writeShellApplication {
          name = "exec-stop";
          runtimeInputs = [ podman ];
          text = ''
            set -e
            [ "$SERVICE_RESULT" = success ] || podman stop --ignore --cidfile=/run/flatnotes/podman-'flatnotes'.ctr-id
          '';
        };
        ExecStopPostScript = pkgs.writeShellApplication {
          name = "exec-stop-post";
          runtimeInputs = [ podman ];
          text = ''
            set -e
            podman rm -f --ignore --cidfile=/run/flatnotes/podman-'flatnotes'.ctr-id
          '';
        };
      in

      {
        description = "Flatnotes";
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = config.users.users.flatnotes.name;
          WorkingDirectory = cfg.userDir;
          StateDirectory = "flatnotes";
          RuntimeDirectory = "flatnotes";
          EnvironmentFile =
            let
              environment = pkgs.writeFile "flatnotes_env" ''
                PODMAN_SYSTEMD_UNIT='flatnotes.service'
                XDG_RUNTIME_DIR='/run/flatnotes'
              '';
            in
            "${environment}";
          ExecStartPre = "${ExecStartPreScript}/bin/exec-start-pre";
          ExecStart = "${ExecStartScript}/bin/exec-start";
          ExecStop = "${ExecStopScript}/bin/exec-stop";
          ExecStopPost = "${ExecStopPostScript}/bin/exec-stop-post";
          NotifyAccess = "all";
          Restart = "always";
          TimeoutStartSec = 0;
          TimeoutStopSec = 120;
          Type = "notify";
        };
      };

    users.groups.flatnotes = {
      gid = 7331;
    };
    users.users.flatnotes = {
      uid = 1337;
      description = "For Flatnotes container";
      group = config.users.groups.flatnotes.name;
      homeMode = "0750";
      isNormalUser = true;
      linger = true; # this is needed to run podman in rootless mode
    };

    virtualisation.podman.enable = true;
  };
}
