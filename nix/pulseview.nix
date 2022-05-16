{ pkgs, pulseview, fetchFromGitHub, fetchurl, qttools, version, sha256, libsigrokVersion, libsigrokSha256, libsigrokdecodeVersion, libsigrokdecodeSha256 }:

let
  pulseviewBase = pulseview.override {
    libsigrok = (pkgs.callPackage ./libsigrok.nix {
      version = libsigrokVersion; sha256 = libsigrokSha256;
    });
    libsigrokdecode = (pkgs.callPackage ./libsigrokdecode.nix {
      version = libsigrokdecodeVersion; sha256 = libsigrokdecodeSha256;
    });
  };
in (pulseviewBase.overrideAttrs (oldAttrs: let
#  nextSrc = fetchurl {
#    url = "https://sigrok.org/download/source/pulseview/${oldAttrs.pname}-${version}.tar.gz";
#    inherit sha256;
#  };

  nextSrc = fetchFromGitHub {
    owner = "sigrokproject";
    repo = oldAttrs.pname;
    rev = version;
    inherit sha256;
  };
in {
  inherit version;
  src = nextSrc;

  buildInputs = (oldAttrs.buildInputs or []) ++ [ qttools ];

  # Remove old patches, as they are already merged!
  patches = [
  ];

}))
