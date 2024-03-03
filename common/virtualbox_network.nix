{ name, net_device }: {
  virtualbox = {
    vmName = name;
    params = {
      nic1 = "bridged";
      bridgeadapter1 = net_device;
    };
  };
}
