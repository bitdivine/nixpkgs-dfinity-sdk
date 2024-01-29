{
  description = "IC SDK";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        resolvedSystem =
          if system == "aarch64-darwin"
          then "x86_64-darwin"
          else system;

        makeVersion = { systems, version }: (pkgs.stdenv.mkDerivation {
          name = "dfinity-sdk-${version}-${resolvedSystem}";
          inherit version;
          system = resolvedSystem;
          src = pkgs.fetchzip {
            sha256 =
              if builtins.hasAttr resolvedSystem systems
              then systems.${resolvedSystem}.sha256
              else throw ("unsupported system: " + resolvedSystem);
            stripRoot = false;
            url = builtins.concatStringsSep "/" [
              "https://sdk.dfinity.org"
              "downloads"
              "dfx"
              version
              "${resolvedSystem}"
              "dfx-${version}.tar.gz"
            ];
          };
          nativeBuildInputs = [
            pkgs.makeWrapper
          ] ++ pkgs.lib.optional pkgs.stdenv.isLinux [
            pkgs.glibc.bin
            pkgs.patchelf
            pkgs.which
          ];
          # Use `find $(dfx cache show) -type f -executable -print` on macOS to
          # help discover what to symlink.
          installPhase =
            let
              libPath = pkgs.lib.makeLibraryPath [
                pkgs.stdenv.cc.cc.lib # libstdc++.so.6
              ];
            in ''
              export HOME=$TMP

              ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              local LD_LINUX_SO=$(ldd $(which iconv)|grep ld-linux-x86|cut -d' ' -f3)
              local IS_STATIC=$(ldd ./dfx | grep 'not a dynamic executable')
              local USE_LIB64=$(ldd ./dfx | grep '/lib64/ld-linux-x86-64.so.2')
              chmod +rw ./dfx
              test -n "$IS_STATIC" || test -z "$USE_LIB64" || \
                patchelf \
                  --set-interpreter "$LD_LINUX_SO" \
                  --set-rpath "${libPath}" \
                  ./dfx
              ''}

              ./dfx cache install

              local CACHE_DIR="$out/.cache/dfinity/versions/${version}"
              mkdir -p "$CACHE_DIR"
              cp --preserve=mode,timestamps -R $(./dfx cache show)/. $CACHE_DIR

              mkdir -p $out/bin

              for binary in $(ls $CACHE_DIR); do
                ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
                local BINARY="$CACHE_DIR/$binary"
                test -f "$BINARY" || continue
                local IS_STATIC=$(ldd "$BINARY" | grep 'not a dynamic executable')
                local USE_LIB64=$(ldd "$BINARY" | grep '/lib64/ld-linux-x86-64.so.2')
                chmod +rw "$BINARY"
                test -n "$IS_STATIC" || test -z "$USE_LIB64" || patchelf --set-interpreter "$LD_LINUX_SO" "$BINARY"
                ''}
                ln -s $CACHE_DIR/$binary $out/bin/$binary
              done
            '';
            doInstallCheck = true;
            postInstallCheck = ''
              $out/bin/dfx --version
            '';
            meta = {
              description = "Software Development Kit for creating and managing canister smart contracts on the ICP blockchain";
              homepage = "https://github.com/dfinity/sdk";
              license = pkgs.lib.licenses.asl20;
            };
          }
        );
      in
      {
        packages = {
          default = self.packages."${system}".ic_sdk-0_15_2;

          ic_sdk-0_15_2 = makeVersion {
            systems = {
              "x86_64-darwin" = {
                # sha256 = pkgs.lib.fakeSha256;
                sha256 = "sha256-ZrZ+/3+zAd8DPxi+V/APQP8lNAT2IKG48gTBX72chWg=";
              };
              "x86_64-linux" = {
                # sha256 = pkgs.lib.fakeSha256;
                sha256 = "sha256-lMsKVb1lJed6Edp6aHWe7hqbTuaTLwzEGrhU/r31Pew=";
              };
            };
            version = "0.15.2";
          };
        };
      }
    );
}
