{defaultGateway, ...}: {
  networking = {
    firewall.enable = true;
    useDHCP = false;
    inherit defaultGateway;
    nameservers = [ "208.67.222" "208.67.220.220" ];
    networkmanager.enable = true;
  };

  # Users and groups
  users.mutableUsers = false;
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # you should put here your ssh public key.
    ];
    # you can uncomment the next line to set a default password and allow login without ssh
    # initialPassword = "admin";
  };
  # Allow members of 'wheel' group to execute any command without a password
  security.sudo.wheelNeedsPassword = false;

  # Enable the SSH daemon for remote management
  services.openssh = {
    enable = true;
    allowSFTP = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # WARN: `require-sigs = false` will allow the machine to download binaries served through
  # ssh without signing them. Use this only for experimentation and iteration.
  nix.settings.require-sigs = false;

  system.stateVersion = "24.05";
}
