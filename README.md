# s3ql.nix

[![build](https://github.com/gvolpe/s3ql.nix/actions/workflows/ci.yml/badge.svg)](https://github.com/gvolpe/s3ql.nix/actions/workflows/ci.yml)

NixOS module for managing the [S3QL file system](https://github.com/s3ql/s3ql) via `systemd` services.

## Usage

Add input to your Nix flake:

```nix
inputs = {
  s3ql-nix.url = github:gvolpe/s3ql.nix;
}
```

Add module to your NixOS configuration, e.g.

```nix
outputs = {
  nixosConfigurations = {
    metropolis = lib.nixosSystem {
      modules = [
        s3ql-nix.nixosModules.default
        ./hosts/metropolis/configuration.nix
      ];
    };
  };
}
```

Use the module options in your NixOS configuration, e.g.

```nix
{ ... }:

{
  services.s3ql = {
    enable = true;

    settings = {
      bucket = {
        url = "s3c4://nbg1.your-objectstorage.com/bucket-name/s3ql";
        name = "nbg1";
      };
      backendOptions = [ "sig-region=nbg1" ];
      cache = {
        directory = "/home/admin/.s3ql";
        size = 30000000; # 30 GBs
      };
      mountpoint = "/mnt/s3ql";
      mkfs = {
        flag = "/var/lib/s3ql-mkfs-done";
        skip = false;
      };
      fsck = {
        enable = true;
        schedule = "*-*-01..07 02:30:00";
        skipIfUnitsActive = [
          "borgbackup-job-media.service"
          "s3-replica.service"
        ];
      };
    };
  };
}
```

Set `settings.backendOptions` for S3QL backend-specific authinfo2 options. For S3-compatible V4 backends, this is where values such as `sig-region=nbg1` belong.

The monthly `s3ql-fsck.service` is opt-in. It writes a stamp under `settings.fsck.directory`, skips if any configured `skipIfUnitsActive` unit is still active or activating, stops `s3ql-mount.service`, verifies the mountpoint is unmounted, and then runs `fsck.s3ql` without `--force-remote`.

This practice is [recommended upstream](https://github.com/s3ql/s3ql/blob/b285b820711fadc120e0205619ae5ab7b5e67a96/src/s3ql/mount.py#L601). Without it, you may see this warning in your logs when mounting your S3QL filesystem.

```console
Aug 11 06:42:34 metropolis run[626107]: WARNING: Last file system check was more than 1 month ago, running fsck.s3ql is recommended.
```
