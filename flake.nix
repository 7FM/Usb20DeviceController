{
  description = "env flake";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.nixpkgs_latest.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, nixpkgs_latest, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs_latest = nixpkgs_latest.legacyPackages.${system};

      my-dummy-fpga-tools = (with pkgs_latest; stdenv.mkDerivation {
          pname = "my-dummy-fpga-tools";
          version = "0.0.1";
          src = ./.;
          nativeBuildInputs = [
            cmake
            pkg-config
            libusb
          ];

          installPhase = ''
            mkdir -p $out/bin
            cp driver/dummyUsbDriver $out/bin
            cp tools/annotation_reader/annotation_reader $out/bin
            cp tools/tla_to_vcd/tla_to_vcd $out/bin
            cp tools/vcd_annotation_masking/vcd_annotation_masking $out/bin
            cp tools/vcd_signal_merger/vcd_signal_merger $out/bin
            cp tools/vcd_real_thresholder/vcd_real_thresholder $out/bin
            cp tools/vcd_concat/vcd_concat $out/bin
            cp tools/vcd_time_to_clk/vcd_time_to_clk $out/bin
          '';
        }
      );
    in rec {
      defaultApp = flake-utils.lib.mkApp {
        drv = defaultPackage;
      };
      defaultPackage = my-dummy-fpga-tools;
      devShell = pkgs_latest.mkShell {
        buildInputs = [
          my-dummy-fpga-tools
        ];

        nativeBuildInputs = let
          verilatorVersion = "4.224";
          verilatorSha256 = "sha256-Kn44yWkNcOLkc79HLDTxx5zQn/vqft+hhbvsoUAKR7I=";

          #libsigrokVersion = "0.5.2";
          #libsigrokSha256 = "sha256-TTQfkLYiDT6MslHaz3JsQRZShWEiSPLFLRXfRZChzjw=";
          libsigrokVersion = "f47fee73ac85ca999e91f787980cc59d06133b52";
          libsigrokSha256 = "sha256-VzqnHEktkggpac1GAJ4Mtl6TNAAXCB7eH3n2VaWsW+M=";

          #libsigrokdecodeVersion = "0.5.3";
          #libsigrokdecodeSha256 = "1h1zi1kpsgf6j2z8j8hjpv1q7n49i3fhqjn8i178rka3cym18265";
          libsigrokdecodeVersion = "da253ef59221744f7258720861638bd1ae2e335f";
          libsigrokdecodeSha256 = "sha256-0dUpqOSkNd7YxERMiCSOwFbLirvgVc2bFeEZPY9RUIA=";

          #pulseviewVersion = "0.4.2";
          #pulseviewSha256 = "sha256-8EL3ej4bNb8wZmMw427Dj6uNJIw2k8N7fjXUAcO/q8s=";
          pulseviewVersion = "fe94bf8255145410d1673880932d59573c829b0e";
          pulseviewSha256 = "sha256-XQp/g0QYHgY5SbXo8+OCCdoOGeUu+BSXioJExMh5baM=";
        in with pkgs_latest; [
          dsview # DreamSourceLab's version of pulseview!

          gnumake
          gdb

          #clang
          gtkwave
          icestorm # ice40 tools
          trellis # ecp5 tools
          pkgs.haskellPackages.sv2v
          nextpnrWithGui
          (libsForQt514.callPackage ./nix/pulseview.nix {
            inherit libsigrokVersion libsigrokSha256;
            inherit libsigrokdecodeVersion libsigrokdecodeSha256;
            version = pulseviewVersion; sha256 = pulseviewSha256;
          })

          (yosys.overrideAttrs (oldAttrs: rec {
            patches = [
              ./yosys.patch
            ] ++ (oldAttrs.patches or []);
          }))

          (callPackage ./nix/verilator.nix { inherit verilatorVersion verilatorSha256; })
          zlib # Needed for verilator fst exports
        ];
      };
    }
  );
}
