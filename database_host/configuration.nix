{ config, db_ip, ... }:
let
  influxPorts = [ 8086 ];
  grafanaPorts = [ 3000 ];
  kafkaPorts = [ 9092 9093 ];

in {
  imports = [
    ./model_service.nix
    ../common/sops.nix
    ../common/telegraf-environment.nix
  ];
  networking = {
    hostName = "db-host";
    firewall.allowedTCPPorts = influxPorts ++ grafanaPorts ++ kafkaPorts;
    interfaces = {
      eth0 = {
        ipv4.addresses = [{
          address = db_ip;
          prefixLength = 24; # Equivalent to a netmask of 255.255.255.0
        }];
      };
    };
  };

  services.influxdb2 = {
    enable = true;
    provision = {
      enable = true;
      initialSetup = {
        bucket = "dev";
        organization = "devorg";
        passwordFile = config.sops.secrets.influxdb_password.path;
        tokenFile = config.sops.secrets.influxdb_token.path;
        username = "devuser";
      };
    };
  };
  users.users.influxdb2 = { extraGroups = [ "secret-readers" ]; };

  environment.etc = {
    "grafana/dashboards/dashboard.json" = {
      enable = true;
      source = ./dashboard.json;
    };
  };

  services.grafana = {
    enable = true;
    settings = { server.http_addr = "0.0.0.0"; };
    provision = {
      enable = true;
      dashboards.settings = {
        apiVersion = 1;
        providers = [{
          name = "FileDashboards";
          type = "file";
          disableDeletion = true;
          updateIntervalSeconds = 5;
          allowUiUpdates = true;
          options = {
            path = "/etc/grafana/dashboards";
            foldersFromFilesStructure = true;
          };
        }];
      };
      datasources.settings = {
        apiVersion = 1;
        datasources = [{
          name = "InfluxDB2Flux";
          type = "influxdb";
          url = "http://${db_ip}:8086";
          jsonData = {
            version = "Flux";
            organization = "devorg";
            defaultBucket = "dev";
          };
          secureJsonData = {
            token = "$__file{${config.sops.secrets.influxdb_token.path}}";
          };
        }];
      };
    };
  };
  users.users.grafana = { extraGroups = [ "secret-readers" ]; };

  services.apache-kafka = {
    enable = true;
    formatLogDirs = true;
    formatLogDirsIgnoreFormatted = true;
    clusterId = "EKSv6KSoRIitS7jJiOjrvg";
    settings = {
      "broker.id" = 1;
      # Listeners
      "listeners" = [ "PLAINTEXT://${db_ip}:9092" "CONTROLLER://:9093" ];
      "advertised.listeners" = "PLAINTEXT://${db_ip}:9092";
      "controller.listener.names" = "CONTROLLER";
      "log.dirs" = [ "/var/lib/kafka/logs" ];
      # KRaft mode
      "process.roles" = "broker,controller";
      "node.id" = 1;
      "controller.quorum.voters" = "1@localhost:9093";
      # Disable ZooKeeper
      "zookeeper.connect" = "";
      # Other settings
      "num.network.threads" = 3;
      "num.io.threads" = 8;
      "socket.send.buffer.bytes" = 102400;
      "socket.receive.buffer.bytes" = 102400;
      "socket.request.max.bytes" = 104857600;
      "num.partitions" = 1;
      "num.recovery.threads.per.data.dir" = 1;
      "offsets.topic.replication.factor" = 1;
      "transaction.state.log.replication.factor" = 1;
      "transaction.state.log.min.isr" = 1;
      "log.retention.hours" = 168;
      "log.segment.bytes" = 1073741824;
      "log.retention.check.interval.ms" = 300000;
      "group.initial.rebalance.delay.ms" = 0;
    };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/kafka-logs 0755 kafka kafka - -" ];
  users.users.kafka = {
    isSystemUser = true;
    group = "kafka";
  };
  users.groups.kafka = { };

  services.model = {
    enable = true;
    kafkaAdress = "${db_ip}:9092";
  };

  services.telegraf = {
    enable = true;
    environmentFiles = [ "/run/secrets_derived/influxdb_token.env" ];
    extraConfig = {
      inputs = {
        kafka_consumer = {
          brokers = [ "${db_ip}:9092" ];
          topics = [ "model" ];
          data_format = "json_v2";
          json_v2 = [{
            measurement_name = "model";
            timestamp_path = "timestamp";
            timestamp_format = "unix_ns";

            tag = [{ path = "name"; }];
            field = [{
              path = "value";
              type = "float";
            }];
          }];
        };
      };
      outputs = {
        file = { files = [ "stdout" ]; };
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

