{
  description = "NixOS module for the S3QL file system";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, self }:
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
            pkgs = import nixpkgs { inherit system; };
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            buildInputs = [ pkgs.s3ql ];
          };
        }
      );

      nixosModules.default = import ./modules/s3ql.nix;
    };
}
