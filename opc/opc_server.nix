{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.opc_server;
  interpreter = pkgs.python311.withPackages (ps: with ps; [ asyncua ]);
in {
  options.services.opc_server = {
    enable = mkEnableOption "Mock OPC Server";
    scriptPath = mkOption {
      type = types.path;
      default = "/path/to/your/server.py";
      description = "Path to the Python script to execute.";
    };
    user = mkOption {
      type = types.str;
      default = "nobody";
      description = "User under which the Python script will run.";
    };
    group = mkOption {
      type = types.str;
      default = "nogroup";
      description = "Group under which the Python script will run.";
    };
  };
  config = mkIf cfg.enable {
    systemd.services.opc_server = {
      description = "Mock OPC Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${interpreter}/bin/python ${cfg.scriptPath}";
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        WorkingDirectory = "/";
      };
    };
  };
}
