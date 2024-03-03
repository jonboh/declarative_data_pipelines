{ collector_ip, db_ip, ... }: {
  imports = [ ../common/sops.nix ../common/telegraf-environment.nix ];
  networking = {
    hostName = "ot-collector";
    interfaces.eth0.ipv4.addresses = [{
      address = collector_ip;
      prefixLength = 24; # Equivalent to a netmask of 255.255.255.0
    }];
  };

  services.telegraf = {
    enable = true;
    environmentFiles = [ "/run/secrets_derived/influxdb_token.env" ];
    extraConfig = {
      inputs = {
        opcua_listener = {
          name = "opc_server";
          endpoint = "opc.tcp://192.168.0.5:4840";
          security_policy = "None";
          security_mode = "None";
          nodes = [
            {
              name = "Pressure";
              namespace = "2";
              identifier_type = "i";
              identifier = "3";
            }
            {
              name = "SlowSensor";
              namespace = "2";
              identifier_type = "i";
              identifier = "4";
            }
            {
              name = "Temperature";
              namespace = "2";
              identifier_type = "i";
              identifier = "2";
            }
          ];
        };

      };
      outputs = {
        file = { files = [ "stdout" ]; };
        kafka = {
          brokers = [ "192.168.0.10:9092" ];
          topic = "opc";
          data_format = "json";
          json_timestamp_units = "1ns";
        };
        influxdb_v2 = [{
          urls = [ "http://${db_ip}:8086" ];
          token = "$INFLUXDB_TOKEN";
          organization = "devorg";
          bucket = "dev";
        }];
      };
    };
  };
  users.users.telegraf = { extraGroups = [ "secret-readers" ]; };

}

