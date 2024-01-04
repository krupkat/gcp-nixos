{ config, ... }:

let
  certDir = config.security.acme.certs."tomaskrupka.cz".directory;
in
{
  sops = {
    defaultSopsFile = ./secrets/gcp-instance.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "websupport/dns/api_key" = {
        reloadUnits = [ "acme-tomaskrupka.cz.service" ];
      };

      "websupport/dns/secret" = {
        reloadUnits = [ "acme-tomaskrupka.cz.service" ];
      };

      "websupport/dyn_dns/api_key" = { };
      "websupport/dyn_dns/secret" = { };

      "google/oauth/client_id" = {
        restartUnits = [ "vouch-proxy.service" ];
      };

      "google/oauth/secret" = {
        restartUnits = [ "vouch-proxy.service" ];
      };

      "mosquitto/red" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        reloadUnits = [ "mosquitto.service" ];
      };

      "mosquitto/tiny" = {
        owner = config.users.users.mosquitto.name;
        group = config.users.users.mosquitto.group;
        reloadUnits = [ "mosquitto.service" ];
      };

      "vouch/jwt_secret" = {};
    };

    templates = {
      "vouch.yaml".content = ''
        vouch:
          port: 9090
          domains:
            - tomaskrupka.cz
          cookie:
            domain: tomaskrupka.cz
          whitelist:
            - tomas@krupkat.cz
          tls:
            cert: ${certDir}/cert.pem
            key: ${certDir}/key.pem
          jwt:
            secret: ${config.sops.placeholder."vouch/jwt_secret"}
        oauth:
          provider: google
          client_id: ${config.sops.placeholder."google/oauth/client_id"}
          client_secret: ${config.sops.placeholder."google/oauth/secret"}
          callback_urls:
            - https://vouch.tomaskrupka.cz/auth
          scopes:
            - email
      '';

      "websupport_dns.conf".content = ''
        WEBSUPPORT_API_KEY='${config.sops.placeholder."websupport/dns/api_key"}'
        WEBSUPPORT_SECRET='${config.sops.placeholder."websupport/dns/secret"}'
      '';

      "inadyn.conf".content = ''
        # In-A-Dyn v2.0 configuration file format
        period          = 600
        user-agent      = Mozilla/5.0

        custom websupport {
            ssl            = true
            username       = ${config.sops.placeholder."websupport/dyn_dns/api_key"}
            password       = ${config.sops.placeholder."websupport/dyn_dns/secret"}
            checkip-server = ifconfig.me
            checkip-path   = /ip
            checkip-ssl    = true
            ddns-server    = dyndns.websupport.cz
            ddns-path      = "/nic/update?hostname=%h&myip=%i"
            hostname       = { "tomaskrupka.cz", "www.tomaskrupka.cz", "node-red.tomaskrupka.cz", "vouch.tomaskrupka.cz" }
        }
      '';

      "nodered.settings.js" = {
        owner = config.users.users.node-red.name;
        group = config.users.users.node-red.group;
        path = "/var/lib/node-red/settings.js";
        content = ''
          module.exports = {
              flowFile: 'flows.json',
              flowFilePretty: true,

              https: {
                  key: require("fs").readFileSync('${certDir}/key.pem'),
                  cert: require("fs").readFileSync('${certDir}/cert.pem')
              },

              requireHttps: true,
              uiPort: process.env.PORT || 1880,

              diagnostics: {
                  enabled: true,
                  ui: true,
              },

              runtimeState: {
                  enabled: false,
                  ui: false,
              },
              logging: {
                  console: {
                      level: "info",
                      metrics: false,
                      audit: false
                  }
              },

              exportGlobalContextKeys: false,
              externalModules: {},

              editorTheme: {
                  palette: {},
                  projects: {
                      enabled: false,
                      workflow: {
                          mode: "manual"
                      }
                  },
                  codeEditor: {
                      lib: "monaco",
                      options: {
                      }
                  }
              },

              functionExternalModules: true,
              functionGlobalContext: {},
              debugMaxLength: 1000,
              mqttReconnectTime: 15000,
              serialReconnectTime: 15000,

              dashboard: {
                  middleware: (request, response, next) => {
                      console.log('User name:', request.headers['x-vouch-user'])
                      next()
                  }
              },
          }
        '';
      };
    };
  };
}
