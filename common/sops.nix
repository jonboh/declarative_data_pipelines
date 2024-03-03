{
  users.groups.secret-readers = { };
  sops.age.keyFile =
    "/home/admin/master-age.key"; # probably not the best place, but eases instructions
  sops.secrets.influxdb_token = {
    format = "binary";
    group = "secret-readers";
    mode = "0440"; # Readable by the owner and group
    sopsFile = ../secrets/influxdb_token;
  };
  sops.secrets.influxdb_password = {
    format = "binary";
    group = "secret-readers";
    mode = "0440"; # Readable by the owner and group
    sopsFile = ../secrets/influxdb_password;
  };
}
