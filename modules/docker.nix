{ config, pkgs, lib, ... }:

let
  transcribeComposeFile = ../opt/docker-compose/live-transcribe/docker-compose.yml;
  transcribeConfigFile  = ../opt/docker-compose/live-transcribe/config.yaml;
  hasDockerSecret       = builtins.pathExists ../secrets/dockerhub-credentials.age;
in
{
  warnings = lib.optional (!hasDockerSecret)
    "secrets/dockerhub-credentials.age not found — Docker Hub auth will not be configured";

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

  age.secrets.dockerhub-credentials = lib.mkIf hasDockerSecret {
    file = ../secrets/dockerhub-credentials.age;
  };

  # Authenticate the Docker daemon with DockerHub before any pulls happen.
  # Credentials come from the agenix-managed secret (JSON: {"username":"...","password":"..."}).
  # Runs once per boot as a oneshot; restarts automatically if the secret is rotated.
  systemd.services.docker-login = lib.mkIf hasDockerSecret {
    description = "Authenticate Docker daemon with DockerHub";
    after    = [ "docker.service" ];
    requires = [ "docker.service" ];
    before   = [ "transcribe-docker.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ config.age.secrets.dockerhub-credentials.path ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      creds="${config.age.secrets.dockerhub-credentials.path}"
      user=$(${pkgs.jq}/bin/jq -r .username "$creds")
      pass=$(${pkgs.jq}/bin/jq -r .password "$creds")
      echo "$pass" | ${pkgs.docker}/bin/docker login -u "$user" --password-stdin
    '';
  };

  # Start transcribe via docker-compose on boot (after Docker is ready)
  systemd.services.transcribe-docker = {
    description = "Docker Compose (port 8885)";
    # if image requires auth, ensure docker-login runs first;
    # after    = [ "docker.service" "network-online.target" ]
    #            ++ lib.optional hasDockerSecret "docker-login.service";
    # requires = [ "docker.service" ]
    #            ++ lib.optional hasDockerSecret "docker-login.service";
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
