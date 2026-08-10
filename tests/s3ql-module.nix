{ lib, module, pkgs }:

let
  mountpoint = "/mnt/s3ql";
  bucketUrl = "s3c://example.invalid/s3ql-test";

  testConfig = (lib.nixosSystem {
    modules = [
      module
      {
        services.s3ql = {
          enable = true;

          secrets = {
            accessKey = "/run/secrets/s3ql-access-key";
            passphrase = "/run/secrets/s3ql-passphrase";
            secretKey = "/run/secrets/s3ql-secret-key";
          };

          settings = {
            inherit mountpoint;
            bucket = {
              name = "ci";
              url = bucketUrl;
            };
            cache = {
              directory = "/var/cache/s3ql";
              size = 1024;
            };
            mkfs = {
              flag = "/var/lib/s3ql/mkfs-done";
              skip = true;
            };
            threads = 2;
          };
        };
        system.stateVersion = "25.05";
      }
    ];
    system = pkgs.stdenv.hostPlatform.system;
  }).config;

  services = testConfig.systemd.services;
  mounts = testConfig.systemd.mounts;

  authService = services.s3ql-auth;
  fsService = services.s3ql-fs;
  mountService = services.s3ql-mount;

  mountUnit = lib.findFirst (mount: mount.name == "mnt-s3ql.mount") null mounts;

  assertCheck = name: condition:
    lib.assertMsg condition "s3ql module test failed: ${name}";

  checks = [
    (assertCheck "enables the module" testConfig.services.s3ql.enable)
    (assertCheck "derives the mount unit name from the mountpoint"
      (testConfig.services.s3ql.settings.mountUnitName == "mnt-s3ql.mount"))
    (assertCheck "creates the mountpoint with tmpfiles"
      (lib.elem "d ${mountpoint} 0755 root root -" testConfig.systemd.tmpfiles.rules))

    (assertCheck "registers the synthetic systemd mount"
      (mountUnit != null))
    (assertCheck "points the synthetic mount at the S3QL mountpoint"
      (mountUnit != null && mountUnit.where == mountpoint))
    (assertCheck "uses the S3 bucket URL as the synthetic mount source"
      (mountUnit != null && mountUnit.what == bucketUrl))
    (assertCheck "orders the synthetic mount after s3ql-mount"
      (mountUnit != null && mountUnit.requires == [ "s3ql-mount.service" ]))

    (assertCheck "generates the auth setup service"
      (authService.description == "s3ql authfile setup"))
    (assertCheck "keeps the auth setup service oneshot"
      (authService.serviceConfig.Type == "oneshot"))
    (assertCheck "runs auth setup as root"
      (authService.serviceConfig.User == "root" && authService.serviceConfig.Group == "root"))
    (assertCheck "uses a generated auth setup command"
      (lib.hasSuffix "/bin/run" authService.serviceConfig.ExecStart))

    (assertCheck "orders fs setup after auth and network"
      (fsService.requires == [ "network-online.target" "s3ql-auth.service" ]))
    (assertCheck "runs fs setup as a oneshot"
      (fsService.serviceConfig.Type == "oneshot"))
    (assertCheck "skips fs setup when the mountpoint is already active"
      (lib.hasSuffix "/bin/run" fsService.serviceConfig.ExecCondition))
    (assertCheck "uses a generated fs setup command"
      (lib.hasSuffix "/bin/run" fsService.serviceConfig.ExecStart))

    (assertCheck "starts the mount service for multi-user systems"
      (mountService.wantedBy == [ "multi-user.target" ]))
    (assertCheck "orders mount service after fs setup"
      (mountService.requires == [ "network-online.target" "s3ql-fs.service" ]))
    (assertCheck "runs mount service as root"
      (mountService.serviceConfig.User == "root" && mountService.serviceConfig.Group == "root"))
    (assertCheck "uses s3ql umount for service shutdown"
      (mountService.serviceConfig.ExecStop == "-${pkgs.s3ql}/bin/umount.s3ql ${mountpoint}"))
  ];
in
assert lib.all (check: check) checks;
pkgs.runCommand "s3ql-module-test" { } ''
  mkdir -p "$out"
  touch "$out/passed"
''
