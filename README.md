# s3ql.nix

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
        url = "s3c://nbg1.your-objectstorage.com/bucket-name/s3ql";
        name = "nbg1";
      };
      cache = {
        directory = "/home/admin/.s3ql";
        size = 30000000; # 30 GBs
      };
      mountpoint = "/mnt/s3ql";
      mkfs = {
        flag = "/var/lib/s3ql-mkfs-done";
        skip = false;
      };
    };
  };
}
```
