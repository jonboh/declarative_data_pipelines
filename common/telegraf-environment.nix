{ pkgs, lib, config, ... }: {
  systemd.services.telegraf = {
    after = [ "telegraf-environment.service" ];
    wants = [ "telegraf-environment.service" ];
    serviceConfig = {
      # Keep retrying if failed to start
      StartLimitIntervalSec = 5;
      StartLimitBurst = 10000;
      Restart = lib.mkForce "always";

    };

  };

  systemd.services.telegraf-environment = {
    description = "Create a dotenv file for Telegraf to consume";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils ];
    script = ''
      set -e
      token=$(cat ${config.sops.secrets.influxdb_token.path})
      mkdir -p /run/secrets_derived/
      echo "INFLUXDB_TOKEN=$token" > /run/secrets_derived/influxdb_token.env
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  sops.secrets.influxdb_token = {
    restartUnits = [ "telegraf-environment.service" "telegraf.service" ];
  };
}
