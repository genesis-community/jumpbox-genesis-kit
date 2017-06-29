Jumpbox Genesis Kit
======================

This is a Genesis Kit for the [jumpbox-boshrelease][1]. It creates a VM
with persistent users, that can be used as a starting point for connecting
to infrastructure internal to a VPC/Virtual Network in the IaaS.

The jumpbox contains a multitude of utilities useful for managing and interacting
with BOSH, Cloud Foundry, Concourse, and other related components.

Quick Start
-----------

To use it, you don't even need to clone this repository!  Just run
the following (using Genesis v2):

```
# create a jumpbox-deployments repo using the latest version of the jumpbox kit
genesis init --kit jumpbox

# create a jumpbox-deployments repo using v1.0.0 of the jumpbox kit
genesis init --kit jumpbox/1.0.0

# create a my-jumpbox-configs repo using the latest version of the jumpbox kit
genesis init --kit jumpbox -d my-jumpbox-configs
```

Once created, refer to the deployment repo's README for information on creating

Subkits
-------

#### openvpn

Provides an OpenVPN server via the [openvpn-boshrelease][2].

If there is not a VPN present in the IaaS to connect internally to components,
it may be necessary to include the `openvpn` subkit to enable a TLS-based OpenVPN
server on the jumpbox. Access is managed via SSL certificates generated in Vault,
using the OpenVPN server's CA. You can use a VPN client like Tunnelblick or the
OpenVPN Client to connect.

Since OpenVPN is TLS-based, it is possible to run this on a port commonly permitted
through firewals, such as tcp/443. This gives users a high likelihood of their VPN
traveling in various network environment, where things like IPSec might be disallowed.

#### shield

This subkit sets up the SHIELD agent on a jumpbox, so that SHIELD can be used
to backup user home directories.

#### azure

When deploying SHIELD on azure, you may want to consider the `azure` subkit for
reconfiguring the availability zones in play. Since Azure uses availability sets,
rather than zones, there is typically only one zone in play for networks/VMs,
and the availability set would be defined by the Azure CPI automatically, or via
`cloud_properties` in your Cloud Config.

Params
------

#### Base Params

- **params.hostname** - Allows the overriding of the jumpbox's hostname, which
  defaults to being based off the environment name. For example: `us-west-prod-jumpbox`.
- **params.banner** - Allows the specifying of a login banner/MOTD that will be displayed
  as users log into the jumpbox. By default, the standard system MOTD is used.
- **params.hosts** - Allows customization of the `/etc/hosts` file. Should be specified as
  a list, following the pattern `10.10.10.10 my-custom-host.com`
- **params.env_vars** - Allows for custom environment variables to be set for all users
  of a jump box. This should be a map/hash, where each key is the environment variable name,
  and its value is the value of the env var.

  For example:
  ```
  params:
    env_vars:
      MY_ENV_VAR: true
  ```
- **params.bashrc** - A bash script executed in the context of a `.bashrc` for all users
  on the system. This is here in case additional customization or policies need to be implemented
  across all users of a jumpbox.
- **params.users** - A list of users who should have accounts created on the jumpbox. Each account
  can specify the username, shell, environment template, and SSH keys used to access it. If users are
  removed from this list, their accounts will be deactivated, and home directories moved into an archived
  location, in case data is needed from them still.

  The format of the `users` param will look something like:

  ```
  params:
    users:
    - name: my-user
      shell: /bin/bash
      ssh_keys:
      - ssh-rsa my-key-here-in-base64-encoding
      env: https://github.com/my-user/my-env-repo
  ```

  Environment template repos are optional. If present, they will be cloned into `~/env` upon login.
  If the repo contains a `./install` script, it will be executed.

#### OpenVPN Params

- **params.vpn_client_routes** - A list of networks that should be routed across the VPN connection.
  This is useful for telling VPN clients to send only traffic bound for the VPC over the VPN. Uses
  the format `192.168.0.0 255.255.255.0`.
- **params.dns_servers** - A list of DNS servers that should be advertised to VPN clients. Routes
  to these servers are automatically added to the advertised routes, in case the servers are outside
  the VPC space, but need to be queried from inside it, in order to resolve internal names properly.
- **params.dns_search_domains** - A list of DNS search domains that should be advertised to VPN Clients
  to use when looking up unqualified host names.
- **params.vpn_client_network** - By default, the internal VPN client network used on the jumpbox for
  routing connectings between the VPC and VPN clients is the 172.31.255.0/24 network. Override this
  if your VPC includes this network address space, in favor of one more compatible with your environment.
- **params.vpn_client_netmwask** - This sets the netmask for the above `vpn_client_network`. By default,
  it uses `255.255.255.0`.
- **params.vpn_min_tls_version** - Allows operator to set the minimum TLS version used by OpenVPN.
  By default, it requires TLS version `1.1` or above, but can be configured to only allow `1.2`,
  or anything above version `1.0`.

#### SHIELD Params

- **params.shield_key_vault_path** - A Vault path to the SHIELD daemon's public SSH key
  This is used to authenticate the SHIELD daemon to the agent, when running tasks.

  For example: `secret/us/proto/shield/agent:public`

Cloud Config
------------
By default, this kit uses the following VM types/networks/disk pools from your
Cloud Config. Feel free to override them in your environment, if you would
rather they use entities already existing in your Cloud Foundry:

```
params:
  jumbpox_network:   jumpbox
  jumpbox_disk_pool: jumpbox # should be at least 50GB
  jumpbox_vm_type:   jumpbox # VMs should have at least 1 CPU, and 2GB of memory
```


[1]: https://github.com/cloudfoundry-community/jumpbox-boshrelease
[2]: https://github.com/djb587/openvpn-boshrelease
