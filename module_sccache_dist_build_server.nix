{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.sccache-server;
in {
  options.services.sccache-server = {
    enable = mkEnableOption "Sccache build server service with sops-nix integration";

    package = mkOption {
      type = types.package;
      default = pkgs.sccache-dist;
      description = "Sccache-dist package to use";
    };

    publicAddr = mkOption {
      type = types.str;
      default = "127.0.0.1:10501";
      description = "Public IP address and port that clients will use to connect to this builder";
    };

    syslog = mkOption {
      type = types.enum ["error" "warn" "info" "debug" "trace"];
      default = "warn";
      description = "Client authentication type";
    };

    schedulerUrl = mkOption {
      type = types.str;
      description = "The URL used to connect to the scheduler";
    };

    cacheDir = mkOption {
      type = types.str;
      default = "/var/lib/sccache/toolchains";
      description = "Directory where client toolchains will be stored";
    };

    toolchainCacheSize = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "The maximum size of the toolchain cache, in bytes (default: 10GB)";
    };

    builder = {
      type = mkOption {
        type = types.enum ["overlay"];
        default = "overlay";
        description = "Builder type";
      };

      buildDir = mkOption {
        type = types.str;
        default = "/var/lib/sccache/build";
        description = "The directory under which a sandboxed filesystem will be created for builds";
      };

      bwrapPath = mkOption {
        type = types.str;
        default = "${pkgs.bubblewrap}/bin/bwrap";
        description = "The path to the bubblewrap binary";
      };
    };

    schedulerAuth = {
      type = mkOption {
        type = types.enum ["jwt_token"];
        default = "jwt_token";
        description = "Scheduler authentication type";
      };

      tokenFile = mkOption {
        type = types.str;
        description = "File containing the JWT token for scheduler authentication";
      };
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional configuration options to include in server.conf";
    };
  };

  config = mkIf cfg.enable {
    # Ensure bubblewrap is available
    environment.systemPackages = [pkgs.bubblewrap];

    systemd.services."sccache-server" = {
      description = "Sccache Build Server Service";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      # Server needs to run as root for bubblewrap sandboxing
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        RuntimeDirectory = "sccache_server";
        StateDirectory = "sccache_server";
        ExecStart = "${pkgs.writeShellScript "start-sccache-server" ''
          set -euo pipefail

          CONFIG_FILE="''${RUNTIME_DIRECTORY}/server.conf"

          # Create necessary directories
          mkdir -p "${cfg.cacheDir}"
          mkdir -p "${cfg.builder.buildDir}"

          # Generate the config file
          cat > "$CONFIG_FILE" << EOF
          cache_dir = "${cfg.cacheDir}"
          public_addr = "${cfg.publicAddr}"
          scheduler_url = "${cfg.schedulerUrl}"
          ${optionalString (cfg.toolchainCacheSize != null) "toolchain_cache_size = ${toString cfg.toolchainCacheSize}"}

          [builder]
          type = "${cfg.builder.type}"
          build_dir = "${cfg.builder.buildDir}"
          bwrap_path = "${cfg.builder.bwrapPath}"

          [scheduler_auth]
          type = "${cfg.schedulerAuth.type}"
          token = "$(cat ${cfg.schedulerAuth.tokenFile})"

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

          # Start the server
          exec ${cfg.package}/bin/sccache-dist server --config "$CONFIG_FILE" --syslog ${cfg.syslog}
        ''}";
        Environment = [
          "RUNTIME_DIRECTORY=%t/sccache_server"
          "SCCACHE_NO_DAEMON=1"
        ];
      };
    };

    # Create directories with appropriate permissions
    system.activationScripts.sccache-server-dirs = ''
      mkdir -p "${cfg.cacheDir}" "${cfg.builder.buildDir}"
      chmod 700 "${cfg.cacheDir}" "${cfg.builder.buildDir}"
    '';
  };
}

