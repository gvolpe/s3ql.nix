{
  description = "NixOS module for the S3QL file system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    s3ql-source = {
      flake = false;
      url = "github:s3ql/s3ql?ref=s3ql-6.3.0";
    };
  };

  outputs = { nixpkgs, s3ql-source, self }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      checks = forAllSystems (system:
        {
          s3ql-module = import ./tests/s3ql-module.nix {
            inherit (nixpkgs) lib;
            module = self.nixosModules.default;
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ (import ./overlays { inherit s3ql-source; }) ];
            };
          };
        }
      );

      nixosModules.default = import ./modules/s3ql.nix;

      overlays.default = final: prev: {
        s3ql = self.packages.${prev.stdenv.hostPlatform.system}.default;
      };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import ./overlays { inherit s3ql-source; }) ];
          };
        in
        {
          default = pkgs.s3ql;
        }
      );
    };
}
