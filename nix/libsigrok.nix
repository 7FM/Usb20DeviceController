{ pkgs, libsigrok, autoreconfHook, autoconf, automake, fetchFromGitHub, fetchurl, version, sha256 }:

(libsigrok.overrideAttrs (oldAttrs: let
#  nextSrc = fetchurl {
#    url = "https://sigrok.org/download/source/${oldAttrs.pname}/${oldAttrs.pname}-${version}.tar.gz";
#    inherit sha256;
#  };
  nextSrc = fetchFromGitHub {
    owner = "7FM";
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

  #patches = (oldAttrs.patches or []) ++ [
  #  ./libsigrok_vcd_extensions.patch
  #];
}))
