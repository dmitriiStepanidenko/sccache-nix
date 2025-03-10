{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.sccache-scheduler;
in {
  options.services.sccache-scheduler = {
    enable = mkEnableOption "Sccache scheduler service with sops-nix integration";

    package = mkOption {
      type = types.package;
      default = pkgs.sccache-dist;
      description = "Sccache-dist package to use";
    };

    listenAddr = mkOption {
      type = types.str;
      default = "127.0.0.1:10600";
      description = "Socket address the scheduler will listen on";
    };

    syslog = mkOption {
      type = types.enum ["error" "warn" "info" "debug" "trace"];
      default = "warn";
      description = "Client authentication type";
    };

    clientAuth = {
      type = mkOption {
        type = types.enum ["token" "mozilla"];
        default = "token";
        description = "Client authentication type";
      };

      tokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "File containing client authentication token";
      };

      requiredGroups = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Required Mozilla LDAP groups for mozilla auth type";
      };
    };

    serverAuth = {
      type = mkOption {
        type = types.enum ["jwt_hs256"];
        default = "jwt_hs256";
        description = "Server authentication type";
      };

      secretKeyFile = mkOption {
        type = types.str;
        description = "File containing the server authentication secret key";
      };
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional configuration options to include in scheduler.conf";
    };
  };

  config = mkIf cfg.enable {
    systemd.services."sccache-scheduler" = {
      description = "Sccache Scheduler Service";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        User = "sccache";
        Group = "sccache";
        StateDirectory = "sccache_scheduler";
        RuntimeDirectory = "sccache_scheduler";
        ExecStart = "${pkgs.writeShellScript "start-sccache-scheduler" ''
          set -euo pipefail

          CONFIG_FILE="''${RUNTIME_DIRECTORY}/scheduler.conf"

          # Generate the config file
          cat > "$CONFIG_FILE" << EOF
          public_addr = "${cfg.listenAddr}"

          [client_auth]
          type = "${cfg.clientAuth.type}"
          ${
            if cfg.clientAuth.type == "token"
            then ''
              token = "$(cat ${cfg.clientAuth.tokenFile})"
            ''
            else if cfg.clientAuth.type == "mozilla"
            then ''
              required_groups = [${concatMapStringsSep ", " (g: "\"${g}\"") cfg.clientAuth.requiredGroups}]
            ''
            else ""
          }

          [server_auth]
          type = "${cfg.serverAuth.type}"
          secret_key = "$(cat ${cfg.serverAuth.secretKeyFile})"

          ${concatStringsSep "\n" (mapAttrsToList (
              name: value:
                if isAttrs value
                then ''
                  [${name}]
                  ${concatStringsSep "\n" (mapAttrsToList (k: v: "${k} = ${
                      if isBool v
                      then
                        (
                          if v
                          then "true"
                          else "false"
                        )
                      else if isString v
                      then "\"${v}\""
                      else toString v
                    }")
                    value)}
                ''
                else ''
                  ${name} = ${
                    if isBool value
                    then
                      (
                        if value
                        then "true"
                        else "false"
                      )
                    else if isString value
                    then "\"${value}\""
                    else toString value
                  }
                ''
            )
            cfg.extraConfig)}
          EOF

          # Set appropriate permissions
          chmod 600 "$CONFIG_FILE"

          # Start the scheduler
          exec ${cfg.package}/bin/sccache-dist scheduler --config "$CONFIG_FILE" --syslog ${cfg.syslog}
        ''}";
        Environment = [
          "RUNTIME_DIRECTORY=%t/sccache_scheduler"
          "SCCACHE_NO_DAEMON=1"
        ];
      };
    };

    users.users.sccache = {
      isSystemUser = true;
      group = "sccache";
      description = "Sccache scheduler service user";
      home = "/var/lib/sccache";
    };

    users.groups.sccache = {};
  };
}
