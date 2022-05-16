{ pkgs, libsigrokdecode, autoreconfHook, autoconf, automake, python38, fetchFromGitHub, fetchurl, version, sha256 }:

(libsigrokdecode.overrideAttrs (oldAttrs: let
  #nextSrc = fetchurl {
  #  url = "https://sigrok.org/download/source/${oldAttrs.pname}/${oldAttrs.pname}-${version}.tar.gz";
  #  inherit sha256;
  #};

  nextSrc = fetchFromGitHub {
    owner = "sigrokproject";
    repo = oldAttrs.pname;
    rev = version;
    inherit sha256;
  };
in {
  inherit version;
  src = nextSrc;

  nativeBuildInputs = [
    autoreconfHook
    automake
    autoconf
  ] ++ (oldAttrs.nativeBuildInputs or []);
}))
