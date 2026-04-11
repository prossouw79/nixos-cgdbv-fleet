{ pkgs, ... }:

let
  transcribeComposeFile = ../opt/docker-compose/live-transcribe/docker-compose.yml;
  transcribeConfigFile  = ../opt/docker-compose/live-transcribe/config.yaml;
in
{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # Place the transcribe compose file at /opt/docker-compose/transcribe/
  systemd.tmpfiles.rules = [
    "d /opt/docker-compose/transcribe 0755 root root -"
    "L+ /opt/docker-compose/transcribe/docker-compose.yml - - - - ${transcribeComposeFile}"
    "L+ /opt/docker-compose/transcribe/config.yaml - - - - ${transcribeConfigFile}"
  ];

  # Poll for new images every hour and restart if anything changed.
  # docker-compose up -d after a pull only recreates containers whose image changed.
  systemd.services.transcribe-docker-update = {
    description = "Pull latest images for transcribe and restart if changed";
    after    = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type             = "oneshot";
      WorkingDirectory = "/opt/docker-compose/transcribe";
    };
    script = ''
      ${pkgs.docker-compose}/bin/docker-compose pull
      ${pkgs.docker-compose}/bin/docker-compose up -d
    '';
  };

  systemd.timers.transcribe-docker-update = {
    description = "Hourly image update check for transcribe";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "2min";
      OnUnitActiveSec = "5h";
    };
  };

  # Start transcribe via docker-compose on boot (after Docker is ready)
  systemd.services.transcribe-docker = {
    description = "Docker Compose (port 8885)";
    after    = [ "docker.service" ];
    requires = [ "docker.service" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type             = "oneshot";
      RemainAfterExit  = true;
      WorkingDirectory = "/opt/docker-compose/transcribe";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --pull always";
      ExecStop  = "${pkgs.docker-compose}/bin/docker-compose down";
    };
  };
}
