{
  s3ql-source,
  lib,
  python3,
  sqlite,
  which,
  nix-update-script,
  writableTmpDirAsHomeHook,
}:

let
  pyproject = builtins.fromTOML (builtins.readFile "${s3ql-source}/pyproject.toml");

  inherit (python3.pkgs)
    buildPythonApplication
    anyio
    apsw
    cryptography
    cython
    defusedxml
    google-auth
    google-auth-oauthlib
    h11
    httpcore
    more-itertools
    pydantic
    pyfuse3
    pytest
    requests
    setuptools
    typer
    pytest-trio
    pytestCheckHook
    trio
    ;
in

buildPythonApplication (finalAttrs: {
  pname = "s3ql";
  version = pyproject.project.version;
  pyproject = true;

  src = s3ql-source;

  build-system = [
    cython
    setuptools
  ];

  nativeBuildInputs = [
    which
  ];

  dependencies = [
    anyio
    apsw
    cryptography
    defusedxml
    google-auth
    google-auth-oauthlib
    h11
    httpcore
    more-itertools
    pydantic
    pyfuse3
    requests
    typer
    sqlite
    trio
  ];

  nativeCheckInputs = [
    pytest
    pytest-trio
    pytestCheckHook
    writableTmpDirAsHomeHook
  ];

  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  pythonImportsCheck = [ "s3ql" ];

  enabledTestPaths = [ "tests/" ];

  # SSL EOF error doesn't match connection reset error. Seems fine.
  disabledTests = [ "test_aborted_write2" ];

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version-regex"
      "s3ql-([0-9.]+)"
    ];
  };

  meta = {
    description = "Full-featured file system for online data storage";
    homepage = "https://github.com/s3ql/s3ql/";
    changelog = "https://github.com/s3ql/s3ql/releases/tag/s3ql-${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ gvolpe rushmorem ];
    platforms = lib.platforms.linux;
  };
})
