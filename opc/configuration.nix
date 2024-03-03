{ pkgs, ... }: {
  imports = [ ./opc_server.nix ];
  networking = {
    firewall.allowedTCPPorts = [ 4840 ];
    interfaces = {
      eth0 = {
        ipv4.addresses = [{
          address = "192.168.0.5";
          prefixLength = 24; # Equivalent to a netmask of 255.255.255.0
        }];
      };
    };
    hostName = "opc-server";
  };

  environment.systemPackages = with pkgs; [
    python311
    python311Packages.asyncua
  ];

  services.opc_server = {
    enable = true;
    scriptPath = ./server.py; # Replace with the actual path to your script
  };
}

