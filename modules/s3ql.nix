{ config, pkgs, lib, ... }:

let
  cfg = config.services.s3ql;

  authfile = "/root/s3ql-auth";
  authService = "s3ql-auth.service";
  fsService = "s3ql-fs.service";

  mountWaitScript = pkgs.writeShellApplication {
    name = "run";
    runtimeInputs = with pkgs;[ bash coreutils util-linux ];
    text = ''
      timeout 60s bash -c \
        'while ! mountpoint -q ${cfg.settings.mountpoint}; do sleep 2; done'

      mkdir -p ${cfg.settings.mountpoint}/immich
    '';
  };

  execConditionScript = pkgs.writeShellApplication {
    name = "run";
    runtimeInputs = with pkgs;[ bash gnugrep ];
    text = ''
      if grep -q " ${cfg.settings.mountpoint} " /proc/mounts; then
        echo "Mountpoint ${cfg.settings.mountpoint} is already active. Skipping unit start."
        exit 1 # systemd: Skip ExecStart
      fi

      exit 0 # systemd: Continue to ExecStart
    '';
  };

  authScript = pkgs.writeShellScriptBin "run" ''
    AUTHFILE=${authfile}
    S3_ACCESS_KEY=$(cat ${cfg.secrets.accessKey} | tr -d '\n')
    S3_SECRET_KEY=$(cat ${cfg.secrets.secretKey} | tr -d '\n')
    S3_PASSPHRASE=$(cat ${cfg.secrets.passphrase} | tr -d '\n')

    {
      echo "[${cfg.settings.bucket.name}]"
      echo "storage-url: ${cfg.settings.bucket.url}"
      echo "backend-login: $S3_ACCESS_KEY"
      echo "backend-password: $S3_SECRET_KEY"
      echo "fs-passphrase: $S3_PASSPHRASE"
    } > "$AUTHFILE"

    # it needs to have read access only for the current user, otherwise any s3ql command fails
    chmod 600 "$AUTHFILE"
  '';

  fsckScript = pkgs.writeShellApplication {
    name = "run";
    runtimeInputs = with pkgs; [ s3ql ];
    text = ''
      if grep -q ' ${cfg.settings.mountpoint} ' /proc/mounts; then
        echo "Filesystem is already mounted at ${cfg.settings.mountpoint}. Skipping FSCK/MKFS."
        exit 0
      fi

      ${if cfg.settings.mkfs.skip then ''
        if [ ! -f ${cfg.settings.mkfs.flag} ]; then
          fsck.s3ql \
            --authfile ${authfile} \
            --batch \
            --cachedir ${cfg.settings.cache.directory} \
            --force-remote \
            --log syslog \
            ${cfg.settings.bucket.url}
          exit 0
        fi
      '' else ''
        S3_PASSPHRASE=$(cat ${cfg.secrets.passphrase} | tr -d '\n')

        if [ ! -f ${cfg.settings.mkfs.flag} ]; then
          # We pipe the passphrase because for some reason mkfs.s3ql does not read it from the authfile...
          echo "S3QL filesystem is uninitialized. Running mkfs.s3ql..."
          echo -n "$S3_PASSPHRASE" | mkfs.s3ql \
            --authfile ${authfile} \
            --cachedir ${cfg.settings.cache.directory} \
            ${cfg.settings.bucket.url}
          echo "S3QL formatting complete."

          # This ensures the service WILL NOT run on next boot.
          echo "Creating success flag at ${cfg.settings.mkfs.flag}"
          mkdir -p "$(dirname "${cfg.settings.mkfs.flag}")"
          touch "${cfg.settings.mkfs.flag}"
        else
          echo "filesystem already exists, running fsck.s3ql..."
          fsck.s3ql \
            --authfile ${authfile} \
            --batch \
            --cachedir ${cfg.settings.cache.directory} \
            --force-remote \
            --log syslog \
            ${cfg.settings.bucket.url}
          echo "S3QL filesystem has recovered."
        fi

        exit 0 # Explicitly exit with success
      ''}
    '';
  };

  mountScript = pkgs.writeShellApplication {
    name = "run";
    runtimeInputs = with pkgs; [ s3ql ];
    text = ''
      mkdir -p ${cfg.settings.mountpoint}

      mount.s3ql \
        --allow-other \
        --authfile ${authfile} \
        --cachedir ${cfg.settings.cache.directory} \
        --cachesize ${toString cfg.settings.cache.size} \
        --fg \
        --threads ${toString cfg.settings.threads} \
        --log syslog \
        ${cfg.settings.bucket.url} ${cfg.settings.mountpoint}
    '';
  };
in
{
  options.services.s3ql = {
    enable = lib.mkEnableOption "Enable the S3QL file system";

    secrets = {
      accessKey = lib.mkOption {
        description = "The S3 bucket access key file";
        default = "/run/agenix/s3-access-key";
        type = lib.types.path;
      };
      secretKey = lib.mkOption {
        description = "The S3 bucket secret key file";
        default = "/run/agenix/s3-secret-key";
        type = lib.types.path;
      };
      passphrase = lib.mkOption {
        description = "The S3QL passphrase to encrypt the file system";
        default = "/run/agenix/s3-passphrase";
        type = lib.types.path;
      };
    };

    settings = {
      bucket = {
        name = lib.mkOption {
          description = "The remote S3 bucket alias name for MinIO client";
          default = "s3ql-bucket";
          type = lib.types.str;
        };
        url = lib.mkOption {
          description = "The remote S3 bucket URL";
          example = "s3c://hel1.your-objectstorage.com/bucket-name/s3ql";
          type = lib.types.str;
        };
      };
      cache = {
        directory = lib.mkOption {
          description = "The S3QL cache directory";
          default = "/root/.s3ql";
          type = lib.types.path;
        };
        size = lib.mkOption {
          description = "The S3QL cache size in KBs";
          default = 20000000;
          type = lib.types.int;
        };
      };
      mkfs = {
        flag = lib.mkOption {
          description = "The file created after mkfs.s3ql runs successfully, so that subsequent runs are avoided";
          default = "/var/lib/s3ql-mkfs-done";
          type = lib.types.path;
        };
        skip = lib.mkEnableOption "Whether to skip the mkfs.s3ql on first run or not (useful when restoring a machine)";
      };
      mountpoint = lib.mkOption {
        description = "The mountpoint directory --- if it contains a dash (-), mountUnitName needs to be set";
        default = "/mnt/s3ql";
        type = lib.types.path;
      };
      mountUnitName = lib.mkOption {
        description = "The mount unit name";
        # converts /mnt/s3ql to mnt-s3ql.mount
        default =
          let
            stripped = lib.removePrefix "/" cfg.settings.mountpoint;
            unit = builtins.replaceStrings [ "/" ] [ "-" ] stripped;
          in
          "${unit}.mount";
        type = lib.types.str;
      };
      threads = lib.mkOption {
        description = "The number of parallel upload threads";
        default = 8;
        type = lib.types.int;
      };
    };

    external.sshkeys = lib.mkOption {
      description = "The authorized ssh public keys";
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.settings.mountpoint} 0755 root root -"
    ];

    systemd.mounts = [
      {
        name = cfg.settings.mountUnitName;
        requires = [ "s3ql-mount.service" ];
        after = [ "s3ql-mount.service" ];
        where = cfg.settings.mountpoint;
        what = cfg.settings.bucket.url;
        type = "none"; # the mounting is done by the service
        wantedBy = [ "multi-user.target" ];
      }
    ];

    systemd.services = {
      s3ql-auth = {
        description = "s3ql authfile setup";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Group = "root";
          ExecStart = "${authScript}/bin/run";
        };
      };

      s3ql-fs = {
        description = "s3ql mkfs/fsck manager: run only once if uninitialized";

        requires = [ "network-online.target" authService ];
        after = [ "network-online.target" authService ];

        unitConfig.DefaultDependencies = false;
        stopIfChanged = false;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Group = "root";
          ExecCondition = "${execConditionScript}/bin/run";
          ExecStart = "${fsckScript}/bin/run";
          TimeoutStartSec = 0;
          Restart = "on-failure";
          RestartSec = 60;
        };
      };

      s3ql-mount = {
        description = "s3ql mount file system";

        before = [ "multi-user.target" ];
        wantedBy = [ "multi-user.target" ];

        requires = [ "network-online.target" fsService ];
        after = [ "network-online.target" fsService "network.target" ];

        unitConfig.DefaultDependencies = false;
        stopIfChanged = false;

        serviceConfig = {
          Type = "simple";
          RemainAfterExit = true;

          #  prevent systemd from killing sub-threads/wrappers to that s3ql can perform a clean unmount
          KillMode = "process";
          KillSignal = "SIGINT";
          SuccessExitStatus = "0 1 SIGINT";

          ExecCondition = "${execConditionScript}/bin/run";
          ExecStart = "${mountScript}/bin/run";
          ExecStartPost = "${mountWaitScript}/bin/run";
          ExecStop = "-${pkgs.s3ql}/bin/umount.s3ql ${cfg.settings.mountpoint}";

          MountFlags = "shared";
          User = "root";
          Group = "root";
          # give it time to download metadata from S3 when remounting
          TimeoutStartSec = 0;
          # give it time to upload metadata to S3 before systemd kills it
          TimeoutStopSec = "5min";
          # ensures systemd can track the FUSE process
          NotifyAccess = "all";
        };
      };
    };
  };
}
