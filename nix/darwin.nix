# nix-darwin: `services.halo.enable = true;` installs halo and runs `halo start` as a user launchd agent.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.halo;
in
{
  options.services.halo = {
    enable = lib.mkEnableOption "halo, the TSX widget runtime";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The halo package to use.";
    };

    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/Users/me/widgets";
      description = "Config directory passed to `halo start --config`. Defaults to `$XDG_CONFIG_HOME/halo` of the logged-in user.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    launchd.user.agents.halo = {
      # Commands the config runs (exec, poll, hydrate) see the per-user and system profiles.
      path =
        lib.optional (
          config.system.primaryUser or null != null
        ) "/etc/profiles/per-user/${config.system.primaryUser}/bin"
        ++ [ config.environment.systemPath ];
      serviceConfig = {
        ProgramArguments = [
          (lib.getExe cfg.package)
          "start"
        ] ++ lib.optionals (cfg.configDir != null) [
          "--config"
          cfg.configDir
        ];
        RunAtLoad = true;
        # `halo quit` (and a missing config) exit normally and stay stopped; only crashes restart it.
        KeepAlive.Crashed = true;
        ProcessType = "Interactive";
      };
    };
  };
}
