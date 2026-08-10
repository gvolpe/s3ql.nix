{ lib, module, pkgs }:

let
  mountpoint = "/mnt/s3ql";
  bucketUrl = "s3c://example.invalid/s3ql-test";

  testConfig = (lib.nixosSystem {
    modules = [
      module
      {
        nixpkgs.pkgs = pkgs;

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
              skip = false;
            };
            connections = 3;
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

  authStart = authService.serviceConfig.ExecStart;
  fsStart = fsService.serviceConfig.ExecStart;
  mountStart = mountService.serviceConfig.ExecStart;
  mountStop = mountService.serviceConfig.ExecStop;

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
      (lib.hasSuffix "/bin/run" authStart))

    (assertCheck "orders fs setup after auth and network"
      (fsService.requires == [ "network-online.target" "s3ql-auth.service" ]))
    (assertCheck "runs fs setup as a oneshot"
      (fsService.serviceConfig.Type == "oneshot"))
    (assertCheck "skips fs setup when the mountpoint is already active"
      (lib.hasSuffix "/bin/run" fsService.serviceConfig.ExecCondition))
    (assertCheck "uses a generated fs setup command"
      (lib.hasSuffix "/bin/run" fsStart))

    (assertCheck "starts the mount service for multi-user systems"
      (mountService.wantedBy == [ "multi-user.target" ]))
    (assertCheck "orders mount service after fs setup"
      (mountService.requires == [ "network-online.target" "s3ql-fs.service" ]))
    (assertCheck "runs mount service as root"
      (mountService.serviceConfig.User == "root" && mountService.serviceConfig.Group == "root"))
    (assertCheck "uses a generated shutdown command"
      (lib.hasSuffix "/bin/s3ql-stop" mountStop))
  ];
in
assert lib.all (check: check) checks;
pkgs.runCommand "s3ql-module-test" { } ''
  assert_contains() {
    ${pkgs.gnugrep}/bin/grep -F -- "$1" "$2" > /dev/null || {
      echo "s3ql module test failed: expected $2 to contain: $1"
      exit 1
    }
  }

  assert_not_contains() {
    if ${pkgs.gnugrep}/bin/grep -F -- "$1" "$2" > /dev/null; then
      echo "s3ql module test failed: expected $2 not to contain: $1"
      exit 1
    fi
  }

  assert_command_block_not_contains() {
    block="$(${pkgs.gnugrep}/bin/grep -A 4 -F -- "$1" "$2")"
    case "$block" in
      *"$3"*)
        echo "s3ql module test failed: expected $1 block in $2 not to contain: $3"
        exit 1
        ;;
    esac
  }

  assert_contains "storage-url: ${bucketUrl}" ${lib.escapeShellArg authStart}
  assert_contains "backend-login:" ${lib.escapeShellArg authStart}
  assert_contains "backend-password:" ${lib.escapeShellArg authStart}
  assert_contains "fs-passphrase:" ${lib.escapeShellArg authStart}

  assert_contains "fsck.s3ql" ${lib.escapeShellArg fsStart}
  assert_contains "--authfile /root/s3ql-auth" ${lib.escapeShellArg fsStart}
  assert_contains "--batch" ${lib.escapeShellArg fsStart}
  assert_contains "--cachedir /var/cache/s3ql" ${lib.escapeShellArg fsStart}
  assert_contains "--force-remote" ${lib.escapeShellArg fsStart}
  assert_contains "--log syslog" ${lib.escapeShellArg fsStart}
  assert_not_contains "--compress" ${lib.escapeShellArg fsStart}

  assert_contains "mkfs.s3ql" ${lib.escapeShellArg fsStart}
  assert_contains "--authfile /root/s3ql-auth" ${lib.escapeShellArg fsStart}
  assert_contains "--cachedir /var/cache/s3ql" ${lib.escapeShellArg fsStart}
  assert_command_block_not_contains "mkfs.s3ql" ${lib.escapeShellArg fsStart} "--log"

  assert_contains "mount.s3ql" ${lib.escapeShellArg mountStart}
  assert_contains "--allow-other" ${lib.escapeShellArg mountStart}
  assert_contains "--authfile /root/s3ql-auth" ${lib.escapeShellArg mountStart}
  assert_contains "--cachedir /var/cache/s3ql" ${lib.escapeShellArg mountStart}
  assert_contains "--cachesize 1024" ${lib.escapeShellArg mountStart}
  assert_contains "--fg" ${lib.escapeShellArg mountStart}
  assert_contains "--max-connections 3" ${lib.escapeShellArg mountStart}
  assert_contains "--max-threads 2" ${lib.escapeShellArg mountStart}
  assert_contains "--log syslog" ${lib.escapeShellArg mountStart}
  assert_not_contains "--threads" ${lib.escapeShellArg mountStart}

  assert_contains "mountpoint -q ${mountpoint}" ${lib.escapeShellArg mountStop}
  assert_contains "umount.s3ql ${mountpoint}" ${lib.escapeShellArg mountStop}
  assert_contains "printf '%s\\n' \"\$output\" >&2" ${lib.escapeShellArg mountStop}

  mkdir -p "$out"
  touch "$out/passed"
''
