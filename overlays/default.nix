{ s3ql-source }:

final: prev:

{
  inherit s3ql-source;
  s3ql = prev.callPackage ./drv.nix { };
}
