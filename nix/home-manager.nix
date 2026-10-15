# home-manager: `services.halo.enable = true;` installs halo and runs `halo start` as a per-user launchd agent.
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
      description = "Config directory passed to `halo start --config`. Defaults to `$XDG_CONFIG_HOME/halo`.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    launchd.agents.halo = {
      enable = true;
      config = {
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
        # Commands the config runs (exec, poll, hydrate) see the user's profile.
        EnvironmentVariables.PATH = lib.concatStringsSep ":" [
          "${config.home.profileDirectory}/bin"
          "/etc/profiles/per-user/${config.home.username}/bin"
          "/run/current-system/sw/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/halo.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/halo.log";
      };
    };
  };
}
