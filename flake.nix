{
  description = "NixOS module for the S3QL file system";

  outputs = { ... }: {
    nixosModules.default = import ./modules/s3ql.nix;
  };
}
