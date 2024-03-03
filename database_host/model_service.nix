{ config, lib, model, ... }:
with lib;
let cfg = config.services.model;
in {
  options.services.model = {
    enable = mkEnableOption "Mock model";
    kafkaAdress = mkOption {
      type = types.str;
      default = "localhost:9092";
      description = "Kafka Adress from which to consume inputs";
    };
  };
  config = mkIf cfg.enable {
    systemd.services.model = {
      description = "Mock Model";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${model}/bin/model";
        User = "nobody";
        Group = "nogroup";
        Restart = "always";
        WorkingDirectory = "/";
        Environment = "KAFKA_ADDRESS=${cfg.kafkaAdress}";
      };
    };
  };
}
