{ inputs, pkgs, ... }:
with pkgs.lib;
let
  # netbird-package-name = "netbird-0-59-5";
  netbird-package-name = "netbird-0-59-7";
  # TODO: I've narrowed down the breakage down to a single commit, see packages/netbird.nix

  vlan = {
    lan1 = 1;
    wan = 2;
    lan2 = 3;
  };
  ip = {
    # beware: 10.0.2.0/24 used by the runNixOSTest on eth0

    # cidrs
    lan1-cidr     = "10.0.3.0/24"; # represents the LAN on one end (machine1 & machine2)
    wan-cidr      = "10.0.4.0/24"; # represents the Internet
    lan2-cidr     = "10.0.5.0/24"; # represents the LAN on the other end (machine3 & machine4)
    netbird-cidr  = "100.0.0.0/24";

    # lan1
    machine1-lan1 = "10.0.3.1"; # represents a server behind NAT
    machine2-lan1 = "10.0.3.2"; # represents a NAT router (lan1 end, lan side)

    # wan
    machine2-wan  = "10.0.4.2";  # represents a NAT router (lan1 end, wan side)
    server-wan    = "10.0.4.10"; # represents the netbird.io Internet service
    machine3-wan  = "10.0.4.3";  # represents a NAT router (lan2 end, wan side)

    # lan2
    machine3-lan2 = "10.0.5.3"; # represents a NAT router (lan2 end, lan side)
    machine4-lan2 = "10.0.5.4"; # represents a server behind NAT (in DMZ)

    # netbird VPN
    machine2-nb   = "100.0.0.2"; # represents a NAT router (netbird side)
    machine4-nb   = "100.0.0.3"; # represents a server on the Internet
  };
in pkgs.testers.runNixOSTest {
  name = "netbird-repro";

  testScript = ''
    ip = {
      'lan1_cidr': "${ip.lan1-cidr}",
      'wan_cidr': "${ip.wan-cidr}",
      'lan2_cidr': "${ip.lan2-cidr}",

      'machine1_lan1': "${ip.machine1-lan1}",
      'machine2_lan1': "${ip.machine2-lan1}",

      'machine2_wan': "${ip.machine2-wan}",
      'server_wan': "${ip.server-wan}",
      'machine3_wan': "${ip.machine3-wan}",

      'machine3_lan2': "${ip.machine3-lan2}",
      'machine4_lan2': "${ip.machine4-lan2}",

      'netbird_cidr': "${ip.netbird-cidr}",
      'machine2_nb': "${ip.machine2-nb}",
      'machine4_nb': "${ip.machine4-nb}",
    }

    ${builtins.readFile ./test-script.py}
  '';

  nodes = let
    netbirdPort = 51821;
    debug = port: {
      # ssh root@localhost -p 22222 -o UserKnownHostsFile="/dev/null" -o StrictHostKeyChecking="no"
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PermitEmptyPasswords = "yes";
        };
      };
      security.pam.services.sshd.allowNullPassword = true;
      virtualisation.forwardPorts = [
        { from = "host"; host.port = port; guest.port = 22; }
      ];
    };
  in {
    server = { config, pkgs, ... }: (recursiveUpdate (debug 22220) {
      environment.systemPackages = with pkgs; [
        netbird-management
      ];
      virtualisation.interfaces = {
        "enp1s0".vlan = vlan.wan;
      };
      networking.interfaces = {
        "enp1s0".ipv4.addresses = [{ address = ip.server-wan; prefixLength = 24; }];
      };
      networking.firewall.enable = false;
      environment.etc = {
        "GeoLite2-City_0.mmdb".source = ../../geolite2/GeoLite2-City.mmdb;
        "geonames_0.db".source = ../../geolite2/geonames_0.db;
      };
      systemd.tmpfiles.rules = [
        "C ${config.systemd.services.netbird-management.serviceConfig.WorkingDirectory}/data/GeoLite2-City_0.mmdb - - - - /etc/GeoLite2-City_0.mmdb"
        "C ${config.systemd.services.netbird-management.serviceConfig.WorkingDirectory}/data/geonames_0.db - - - - /etc/geonames_0.db"
        "d /var/lib/fake-idp - - - - -"
      ];
      services.static-web-server = {
        enable = true;
        root = "/var/lib/fake-idp";
      };
      systemd.services.fake-idp = {
        requiredBy = ["netbird-management.service"];
        before = ["netbird-management.service"];
        script = getExe (pkgs.writeShellApplication {
          name = "fake-idp";
          runtimeInputs = with pkgs; [ bash openssl gnused unixtools.xxd ];
          text = ./fake-idp.sh;
        });
      };
      services.netbird.server = {
        enable = true;
        domain = "netbird.selfhosted";
        management = {
          enable = true;
          domain = ip.server-wan;
          port = 8011;
          extraOptions = ["--disable-geolite-update" "--disable-anonymous-metrics"];
          oidcConfigEndpoint = "http://localhost:8787/.well-known/openid-configuration";
          settings = {
            DataStoreEncryptionKey = "genEVP6j/Yp2EeVujm0zgqXrRos29dQkpvX0hHdEUlQ=";
            HttpConfig = {
              AuthIssuer = "http://localhost:8787";
              AuthAudience = "test-service";
              AuthClientId = "test-key";
            };
            Signal = {
              Proto = "http";
              URI = "${ip.server-wan}:8012";
              Username = "";
              Password = null;
            };
          };
          turnDomain = mkForce "${ip.server-wan}";
        };
        coturn = {
          enable = true;
          domain = "netbird.selfhosted";
          user = "netbird";
          password = "netbird";
        };
        signal = {
          enable = true;
          domain = ip.server-wan;
          port = 8012;
        };
        dashboard.enable = false;
      };
      services.coturn = {
        relay-ips = [ "${ip.server-wan}" ];
        listening-ips = [ "${ip.server-wan}" ];
      };
    });

    machine1 = { config, pkgs, ... }: (recursiveUpdate (debug 22221) {
      environment.systemPackages = with pkgs; [ tcpdump ];
      virtualisation.interfaces = {
        "enp1s0".vlan = vlan.lan1;
      };
      networking.useNetworkd = true;
      networking.interfaces = {
        "enp1s0".ipv4 = {
          addresses = [{ address = ip.machine1-lan1; prefixLength = 24; }];
          routes = [{ address = "0.0.0.0"; prefixLength = 0; via = ip.machine2-lan1; }];
        };
      };
    });

    machine2 = { config, pkgs, ... }: (recursiveUpdate (debug 22222) {
      environment.systemPackages = with pkgs; [ nftables tcpdump ];
      virtualisation.interfaces = {
        "enp1s0".vlan = vlan.lan1;
        "enp2s0".vlan = vlan.wan;
      };
      networking.useNetworkd = true;
      networking.interfaces = {
        "enp1s0".ipv4.addresses = [{ address = ip.machine2-lan1; prefixLength = 24; }];
        "enp2s0".ipv4.addresses = [{ address = ip.machine2-wan; prefixLength = 24; }];
      };
      networking.nftables.enable = true;
      networking.nat = {
        enable = true;
        internalInterfaces = ["enp1s0"];
        externalInterface = "enp2s0";
      };
      services.netbird = {
        package = pkgs."${netbird-package-name}";
        clients.default = {
          hardened = false;
          port = netbirdPort;
          openFirewall = true;
        };
      };
    });

    machine3 = { config, pkgs, ... }: (recursiveUpdate (debug 22223) {
      environment.systemPackages = with pkgs; [ nftables tcpdump ];
      virtualisation.interfaces = {
        "enp1s0".vlan = vlan.lan2;
        "enp2s0".vlan = vlan.wan;
      };
      networking.useNetworkd = true;
      networking.interfaces = {
        "enp1s0".ipv4.addresses = [{ address = ip.machine3-lan2; prefixLength = 24; }];
        "enp2s0".ipv4.addresses = [{ address = ip.machine3-wan; prefixLength = 24; }];
      };
      networking.nftables.enable = true;
      networking.nat = {
        enable = true;
        internalInterfaces = ["enp1s0"];
        externalInterface = "enp2s0";
        dmzHost = ip.machine4-lan2;
        # forwardPorts = [{
        #   destination = "${ip.machine4-lan2}:${toString netbirdPort}";
        #   proto = "udp";
        #   sourcePort = netbirdPort;
        # }];
      };
    });

    machine4 = { config, pkgs, ... }: (recursiveUpdate (debug 22224) {
      environment.systemPackages = with pkgs; [ tcpdump ];
      virtualisation.interfaces = {
        "enp1s0".vlan = vlan.lan2;
      };
      networking.useNetworkd = true;
      networking.interfaces = {
        "enp1s0".ipv4 = {
          addresses = [{ address = ip.machine4-lan2; prefixLength = 24; }];
          routes = [{ address = "0.0.0.0"; prefixLength = 0; via = ip.machine3-lan2; }];
        };
      };
      services.netbird = {
        package = pkgs."${netbird-package-name}";
        clients.default = {
          hardened = false;
          port = netbirdPort;
          openFirewall = true;
        };
      };

      # networking.nftables.enable = true;
      # networking.useDHCP = false;
      # networking.interfaces.eth0.useDHCP = true;
      # systemd.network.wait-online.ignoredInterfaces = [ config.services.netbird.clients.default.interface ];
    });
  };
}