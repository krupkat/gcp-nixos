# gcp-nixos

This is an example project using [NixOS](https://nixos.org/) to declaratively configure a VM with multiple services that can run on a free tier micro instance (see [howto](howto.md) for details).

The configuration is mostly not specific to the cloud service and can be adapted to other providers (e.g. [Amazon EC2](https://nixos.wiki/wiki/Install_NixOS_on_Amazon_EC2)).

## Services overview

Following services are defined using [NixOS options](https://search.nixos.org/options?channel=23.11&from=0&size=50&sort=relevance&type=packages&query=services.).

1. [ACME](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/nixos/modules/security/acme/default.md)
    1. This uses the [lego](https://go-acme.github.io/lego/) client to manage and renew SSL certificates from Let's Encrypt.
    2. Wildcard certificate verification using dns verification check (connecting to [Websupport DNS API](https://rest.websupport.sk/docs/v1.zone))
    3. Auto restarts dependent services upon certificate renewal.
2. [nginx](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
    1. Use as a reverse proxy to manage multiple subdomains and forward traffic to the respective services.
    2. Host a static website on the root domain
    3. Force SSL on all endpoints
    4. Gate specific subdomains behind SSO login using the [auth_request](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html) module and the [vouch-proxy](https://github.com/vouch/vouch-proxy) service.
3. [node-red](https://nodered.org/)
    1. Home automation toolbox
    2. Protected by SSO (https://node-red.tomaskrupka/cz)
4. [mosquitto](https://github.com/eclipse/mosquitto)
    1. mqtt broker with two listeners defined
        1. Unauthenticated traffic for local services
        2. mqtt over SSL for remote connections
5. [restic](https://restic.net/)
    1. Daily backups of user data to a GCS bucket:
        1. node-red data directory
        2. flatnotes data directory
        3. website root

Following services are packaged in the `modules` directory of this repository:

6. [vouch-proxy](https://github.com/vouch/vouch-proxy)
    1. SSO solution for nginx
    2. Configured to use Google OAuth 2.0 and only pass whitelisted users
    3. See details in the `modules/vouch.nix` file
7. [inadyn](https://github.com/troglobit/inadyn)
    1. Dynamic DNS service
    2. Runs periodically to check the VM public address and update DNS records ([Websupport DynDNS API](https://www.websupport.cz/podpora/kb/dyndns/))
    3. See details in the `modules/inadyn.nix` file
8. [flatnotes](https://github.com/dullage/flatnotes)
    1. Personal note taking
    2. Protected by SSO (https://notes.tomaskrupka.cz)
    3. See details in the `modules/flatnotes.nix` file

## Secrets management

The services require quite a few keys / tokens / secrets to be able to run. All the secrets are managed using [sops-nix](https://github.com/Mic92/sops-nix):

- Secrets definitions are in the `secrets.nix` file
- Encrypted secrets are included in the `secrets` directory
- The secrets are decrypted on the VM during system activation and have permissions set to read-only either for root or a specific service user.

## Website content

The static content of the website is expected to be served from `/home/github-actions/www`:
- The `github-actions` user is defined in the configuration file
- The `nginx` user has read access to its home directory
- An authorized ssh public key is configured so that the content can be uploaded from another machine
