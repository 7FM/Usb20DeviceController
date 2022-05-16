{ pkgs, verilator, autoconf, fetchFromGitHub, verilatorVersion, verilatorSha256 }:

(verilator.overrideAttrs (oldAttrs: {
  version = verilatorVersion;
  #src = fetchurl {
  #  url    = "https://www.veripool.org/ftp/${oldAttrs.pname}-${verilatorVersion}.tgz";
  #  sha256 = verilatorSha256;      
  #};
  src = fetchFromGitHub {
    owner = "verilator";
    repo = "verilator";
    rev = "v" + verilatorVersion;
    sha256 = verilatorSha256;      
  };

  nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [
    autoconf
  ];

  preConfigure = (oldAttrs.preConfigure or "") + ''
    autoconf # Generate ./configure script
  '';

  patches = (oldAttrs.patches or []) ++ [
    ./verilator_cpp17_20.patch
  ];
}))
