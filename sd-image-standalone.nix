{ config, lib, pkgs, ... }:

let
  extlinux-conf-builder =
    import ./nixos/modules/system/boot/loader/generic-extlinux-compatible/extlinux-conf-builder.nix {
      pkgs = pkgs.buildPackages;
    };

  crossenv = { lib, buildPythonPackage, fetchPypi }: buildPythonPackage rec {
    pname = "crossenv";
    version = "0.6";
    src = fetchPypi {
      inherit pname version;
      sha256 = "3ee676cf8ab282e7c8f887ea36e2c51fe6cb01a0c61b5fb11e113e88da702545";
    };
    doCheck = false;
  };

  picamera = { lib, buildPythonPackage, fetchPypi }: buildPythonPackage rec {
    pname = "picamera";
    version = "1.13";
    postPatch = ''
      substituteInPlace setup.py \
        --replace "found = False" "found = True"
    '';
    propagatedBuildInputs = with pkgs; [
      raspberrypifw
      raspberrypi-tools
    ];
    src = fetchPypi {
      inherit pname version;
      sha256 = "890815aa01e4d855a6a95dd3ad0953b872a6b954982106407df0c5a31a163e50";
    };
    doCheck = false;
  };

  yolov3_weights = ./yolov3.weights;

  cvlib = { lib, buildPythonPackage, fetchPypi, setuptools, imageio, imutils, numpy, opencv3, pillow, progressbar, requests }: buildPythonPackage rec {
    pname = "cvlib";
    version = "0.2.2";
    src = fetchPypi {
      inherit pname version;
      sha256 = "b1a1dacbdbac8c871e547befa92e80b16b570359cea6314b91bef4ab1036c2c9";
    };
    postConfigure = ''
      substituteInPlace setup.py \
        --replace " 'keras'," ""
      substituteInPlace cvlib/__init__.py \
        --replace "from .gender_detection import detect_gender" ""
    '';
    doCheck = false;
    postInstall = ''
      mkdir -p $out/var/lib
      cp ${yolov3_weights} $out/var/lib
    '';
    propagatedBuildInputs = [
      imageio
      imutils
      numpy
      opencv3
      pillow
      progressbar
      requests
      setuptools
    ];
  };

in
{
  imports = [
    ./nixos/modules/installer/cd-dvd/sd-image.nix
    ./nixos/modules/installer/cd-dvd/channel.nix
  ];

  # Enable WIFI
  hardware.enableRedistributableFirmware = true;

  # Configure nixpkgs for cross-compilation
  nixpkgs = {
    crossSystem = { system = "aarch64-linux"; };
    config = {
      packageOverrides = super: let self = super.pkgs; in {
        git = super.git.override {
          perlSupport = false;
        };
        mesa = super.mesa.override {
          eglPlatforms = [ "x11" "surfaceless" ];
        };
        openjdk8 = super.openjdk8.override {
          enableGnome2 = false;
        };
        openjdk11 = super.openjdk11.override {
          enableGnome2 = false;
        };
      };
    };
  };

  boot.consoleLogLevel = lib.mkDefault 4;

  # Allows early (earlier) modesetting for the Raspberry Pi
  boot.initrd.availableKernelModules = [ "vc4" "bcm2835_dma" "i2c_bcm2835" ];

  # Camera
  boot.kernelModules = [ "bcm2835_v4l2" ];

  # The serial ports listed here are:
  boot.kernelParams = [
    "cma=32M"                   # ensure the virtual console on the RPi3 works.
    "console=ttyS1,115200n8"    # UART
    "console=ttyAMA0,115200n8"  # QEMU
    "console=tty0"
  ];
  boot.kernelPackages = pkgs.linuxPackages_4_19;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.grub.enable = false;
  boot.loader.raspberryPi.enable = true;
  boot.loader.raspberryPi.version = 3;
  boot.loader.raspberryPi.uboot.enable = true;
  boot.loader.timeout = pkgs.lib.mkForce 0;
  boot.tmpOnTmpfs = true;

  documentation.nixos.enable = false;

  sdImage = {
    populateFirmwareCommands = let
      configTxt = pkgs.writeText "config.txt" ''
        kernel=u-boot-rpi3.bin

        # Enable camera support
        start_x=1
        gpu_mem=256

        # Boot in 64-bit mode.
        arm_control=0x200

        # U-Boot used to need this to work, regardless of whether UART is actually used
        # or not. TODO: check when/if this can be removed.
        enable_uart=1

        # Prevent the firmware from smashing the framebuffer setup done by the mainline
      '';
      in ''
        (cd ${pkgs.raspberrypifw}/share/raspberrypi/boot && cp bootcode.bin fixup*.dat start*.elf $NIX_BUILD_TOP/firmware/)
        cp ${pkgs.ubootRaspberryPi3_64bit}/u-boot.bin firmware/u-boot-rpi3.bin
        cp ${configTxt} firmware/config.txt
      '';
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${extlinux-conf-builder} -t 3 -c ${config.system.build.toplevel} -d ./files/boot
    '';
  };

  environment.systemPackages = with pkgs; [
    # Tools
    htop
    raspberrypi-tools
    vim
    # Software
    (python37.withPackages (ps: [
      ((pkgs.newScope ps) cvlib {})
      ((pkgs.newScope ps) picamera {})
    ]))
  ];

  hardware.bluetooth.enable = false;
  hardware.bluetooth.powerOnBoot = false;

  i18n.consoleKeyMap = "fi";
  i18n.defaultLocale = "fi_FI.UTF-8";

# security.pam.u2f.enable = true;
# security.pam.u2f.authFile = ./u2f_keys;
# security.pam.services.datakurre.u2fAuth = true;

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  security.polkit.enable = false;

# services.xserver.desktopManager.surf-display.enable = true;
# services.xserver.displayManager.slim.defaultUser = "datakurre";
# services.xserver.displayManager.slim.enable = true;
# services.xserver.enable = true;
# services.xserver.layout = "fi";
# services.xserver.videoDrivers = [ "vesa" "modesetting" ];
# services.xserver.windowManager.default = "xmonad";
# services.xserver.windowManager.xmonad.enable = true;

  services.openssh.enable = true;
  services.openssh.passwordAuthentication = false;
  services.udisks2.enable = false;

  time.timeZone = "Europe/Helsinki";

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 8080 ];
  networking.hostName = "NixPI3";
  networking.wireless.enable = true;
  networking.wireless.interfaces = [ "wlan0" ];
  networking.wireless.networks."agora-open" = {};

# systemd.services.tweet = let
#   tweet = (import ./tweet { inherit pkgs; }).package;
# in {
#   description = "Tweet my IP address";
#   after = [ "network-online.target" ];
#   wantedBy = [ "multi-user.target" ];
#   path = [ tweet pkgs.nettools ];
#   serviceConfig = {
#     Type = "oneshot";
#     RemainAfterExit = "yes";
#     ExecStart =
#       "${tweet}/lib/node_modules/tweet $$(ifconfig|grep -oE 'inet [0-9\\.]+')";
#   };
# };

  # User configuration
  users.users.datakurre = {
    isNormalUser = true;
    initialPassword = "user";
    description = "Asko Soukka";
    home = "/home/datakurre";
    extraGroups = [
      "audio"
      "input"
      "video"
      "wheel"
    ];
    uid = 1000;
    openssh.authorizedKeys.keyFiles = [ ./atsoukka.pub ];
  };

  # Tell the Nix evaluator to garbage collect more aggressively.
  # This is desirable in memory-constrained environments that don't
  # (yet) have swap set up.
  environment.variables.GC_INITIAL_HEAP_SIZE = "1M";

  networking.firewall.logRefusedConnections = false;
}
