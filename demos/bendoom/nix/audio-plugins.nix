{ lib, alsa-lib, alsa-plugins, libpulseaudio, pipewire, meson, ninja, pkg-config, symlinkJoin }:

let
  inherit (lib.lists) map singleton;

  pulse = alsa-plugins.overrideAttrs {
    buildInputs = [ alsa-lib libpulseaudio ];
    configureFlags = [
      "--disable-jack" "--disable-oss" "--disable-mix" "--disable-usbstream"
      "--disable-arcamav" "--disable-lavrate" "--disable-samplerate"
      "--disable-speexdsp" "--disable-a52" "--enable-pulseaudio"
    ];
  };
  client = pipewire.overrideAttrs {
    pname = "pipewire-client";
    outputs = [ "out" "dev" ];
    patches = [ ];
    nativeBuildInputs = [ meson ninja pkg-config ];
    buildInputs = singleton alsa-lib;
    nativeCheckInputs = [ ];
    mesonFlags = [
      "-Dauto_features=disabled"
      "-Dpipewire-alsa=enabled"
      "-Dalsa=enabled"
      "-Dtests=enabled"
      "-Dexamples=disabled"
      "-Dpipewire-jack=disabled"
      "-Dpipewire-v4l2=disabled"
      "-Ddbus=disabled"
      "-Dflatpak=disabled"
      "-Dvideoconvert=disabled"
      "-Dvideotestsrc=disabled"
      "-Daudiotestsrc=disabled"
      "-Dlegacy-rtkit=false"
      "-Dsession-managers=[]"
      "-Drlimits-install=false"
    ];
    postPatch = "";
    postInstall = "";
    doInstallCheck = false;
    passthru = { };
  };
in
symlinkJoin {
  name = "bendoom-alsa-plugins";
  paths = map (p: "${p}/lib/alsa-lib") [ pulse client ];
  passthru = { inherit pulse client; };
}
