{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs {
        inherit system;
      };
      raspberry_pkgs = import nixpkgs {
        system = "aarch64-linux";
      };
      modulesPath = "${pkgs.path}/nixos/modules";

      # network interface to which the raspberry and virtualbox vms will be connected
      net_device = "enp4s0";
      defaultGateway = "192.168.0.1";
      db_ip = "192.168.0.10";
      opc_ip = "192.168.0.5";
      collector_ip = "192.168.0.7";
    in {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

      devShells.x86_64-linux.default = pkgs.mkShell {
        name = "data-acquisition-demo";
        packages = with pkgs; [
          sops
          age
          zstd
          kafkacat
          pyright
          ruff-lsp
          python311
          python311Packages.asyncua
        ];
        shellHook = ''
          export SOPS_AGE_KEY_FILE=./master-age.key;
        '';
      };

      packages.x86_64-linux = {
        "collector@vbox" = nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          specialArgs = {
            inherit defaultGateway;
            inherit collector_ip;
            inherit db_ip;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./common/configuration.nix
            ./collect_agent/configuration.nix
            (import ./common/virtualbox_network.nix {
              name = "collector";
              net_device = net_device;
            })
          ];
          format = "virtualbox";
        };

        "db@vbox" = nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          specialArgs = {
            inherit defaultGateway;
            inherit db_ip;
            model = self.packages.x86_64-linux.model;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./common/configuration.nix
            ./database_host/configuration.nix
            (import ./common/virtualbox_network.nix {
              name = "db";
              net_device = net_device;
            })
          ];
          format = "virtualbox";
        };

        "opc@vbox" = nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          specialArgs = {
            inherit defaultGateway;
            inherit opc_ip;
          };
          modules = [
            ./common/configuration.nix
            ./opc/configuration.nix
            (import ./common/virtualbox_network.nix {
              name = "opc";
              net_device = net_device;
            })
          ];
          format = "virtualbox";
        };

        model = (import ./model { inherit pkgs; });

      };

      packages.aarch64-linux = {
        opc_raspberry = nixos-generators.nixosGenerate {
          system = "aarch64-linux";
          specialArgs = {
            inherit defaultGateway;
            inherit opc_ip;
          };
          modules = [ ./common/configuration.nix ./opc/configuration.nix ];
          format = "sd-aarch64";
        };
      };

      # With these configuration you are able to push modifications remotely
      # running `nixos-rebuild switch --flake ."<config_name>" --target-host <address>`
      nixosConfigurations = {
        "opc@raspberry" = lib.nixosSystem {
          system = "aarch64-linux";
          pkgs = raspberry_pkgs;
          specialArgs = {
            inherit defaultGateway;
            inherit opc_ip;
          };
          modules = [
            ./common/configuration.nix
            ./opc/configuration.nix
            "${toString modulesPath}/installer/sd-card/sd-image-aarch64.nix"
          ];
        };
        "opc@vbox" = lib.nixosSystem {
          system = "x86_64-linux";
          inherit pkgs;
          specialArgs = {
            inherit defaultGateway;
            inherit opc_ip;
          };
          modules = [
            ./common/configuration.nix
            ./opc/configuration.nix
            "${toString modulesPath}/virtualisation/virtualbox-image.nix"
          ];
        };
        "collector@vbox" = lib.nixosSystem {
          system = "x86_64-linux";
          inherit pkgs;
          specialArgs = {
            inherit defaultGateway;
            inherit collector_ip;
            inherit db_ip;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./common/configuration.nix
            ./collect_agent/configuration.nix
            "${toString modulesPath}/virtualisation/virtualbox-image.nix"
          ];
        };
        "db@vbox" = lib.nixosSystem {
          system = "x86_64-linux";
          inherit pkgs;
          specialArgs = {
            inherit defaultGateway;
            inherit db_ip;
            model = self.packages.x86_64-linux.model;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./common/configuration.nix
            ./database_host/configuration.nix
            "${toString modulesPath}/virtualisation/virtualbox-image.nix"
          ];
        };
      };
    };
}
