# Jumpbox Genesis Kit Manual

The **Jumpbox Genesis Kit** deploys a VM, with persistent users,
that can be used as a starting point for connecting to internal
VPC/VPN infrastructure inside the cloud.

The jumpbox contains a multitude of utilities useful for managing
and interacting with BOSH, Cloud Foundry, Concourse, and other
related components.

# Base Parameters

- `hostname` - Override the jumpbox hostname.  By default, the
  jumpbox VM will be named after the environment, with the suffix
  `-jumpbox` appended.

- `banner` - A login / MOTD banner to display to all users logging
  into the jumpbox over SSH.

- `hosts` - A list of IP address / FQDN lines that should be
  appended to `/etc/hosts`, to override DNS or provide missing
  name records.

- `env_vars` - A map of custom environment variables to be set for
  all users on the jumpbox.  The keys of this map will be taken to
  be environment variable names.

- `bashrc` - Contents of a Bash script that will be executed for
  every user, on every SSH login.  Use with care.

- `users` - A list of users to create accounts for on the jumpbox.

  This is a list of maps.

  Each map represents a single user, and must contain the
  following keys:

  - `username` - The account name
  - `shell` - Login shell, i.e. `/bin/bash` or `/bin/zsh`
  - `ssh_keys` - A list of public SSH keys to authorize for
    password-less authentication against this account.

  Note that this kit does not support SSH accounts that are not
  authenticated via SSH keys; you cannot set up password-based
  user authentication.

## Deployment Parameters

- `jumpbox_disk_pool` - The persistent disk pool that the jumpbox
  VM will use.  This pool must exist in your cloud config.
  Defaults to `jumpbox`.

- `jumpbox_vm_type` - What type of VM to deploy.  This type must
  exist in your cloud config.  Defaults to `jumpbox`.

- `jumpbox_network` - What network to deploy the jumpbox into.
  This network must be defined in your cloud config.  Defaults to
  `jumpbox`.

- `availability_zones` - What BOSH HA availability zones to deploy
  to.  Since jumpbox deployments normally only consist of a single
  VM, this is not useful for high availability.  Defaults to `z1`.

# Available Features

- `azure` - Replaces BOSH's native "availability zones"
  configuration in favor of Azure's "availability set" concept.
  This is required for HA and fault tolerance when running on
  Microsoft Azure.  `genesis new` will auto-detect the need for
  this feature, based on the BOSH director's CPI.

  Activating this feature also activates the following parameters:

  - `azure_availability_set` - The name of the availability set to
    use for HA in Azure.  Defaults to `vault_as`.

- `openvpn` - Provides an OpenVPN server, giving users access to
  the internal infrastructure without requiring an SSH session.
  Intead, users will be issued an X.509 identity certificate which
  will grant them access to connect to the VPN and access internal
  resources from their connecting device (usually their own
  workstation).

  The VPN server works with Tunnelblik, as well as various
  operating system vendor VPN client software.

  Activating this feature also activates the following parameters:

  - `vpn_client_routes` - A list of routes that should be routed
    across the VPN device, instead of the connected clients local
    default gateway.

    These must be specified in dotted-quad notation, i.e.:
    `192.168.0.0 255.255.255.0` (a /24).

  - `dns_servers` - A list of DNS servers that will be advertised
    to connecting VPN clients.  Most VPN client software will set
    these as the canonical system name resolvers while the VPN is
    connected.

  - `dns_search_domains` - A list of DNS search domains that will
    be advertised to connecting VPN clients.  This frees up
    clients from having to type the entire FQDN for name
    resolution to function properly.

  - `vpn_client_network` - A network pool from which to assign IP
    addresses to connected client endpoints.  This defaults to
    `172.31.255.0`, with a `/24` netmask (set separately).

    If the defaults conflict with other IP space you are using in
    your environment (home, work, or otherwise), you can override
    to use something more amenable.

    This value must not contain the `/x` CIDR mask, nor should it
    be accompanied by a dotted-quad network mask.

  - `vpn_client_netmask` - Netmask to use for the client pool.
    Defaults to `255.255.255.0` (a `/24` network with 254 hosts).

  - `vpn_min_tls_version` - The minimum TLS version that OpenVPN
    will require for transactions to proceed.  Defaults to `1.1`,
    but can be downgraded to allow TLS `1.0` or upgraded to
    require TLS `1.2`.

# Available Addons

  - `issue-cert` - Issue an X.509 certificate to a user, so that they
    can connect and authenticate to the VPN.  Requires the `openvpn`
    feature to be active.

  - `revoke-cert` - Revoke an issued X.509 VPN certificate.

  - `renew-cert` - Renew the lifetime of an existing X.509 VPN
    certificate, without changing the key that the user has.

  - `reissue-cert` - Reissue an X.509 VPN certificate, and
    generate a new key in the process.  This is useful if, for
    example, a key has been lost or compromised.  The old
    certificate will be revoked.

  - `inventory` - Run the inventory errand against the deployment.

  - `ssh` - SSH into the jumpbox (interactively).

  - `who` - SSH into the jumpbox and determine who is logged in.

# Examples

To use custom cloud config types:

```
---
kit:
  name:    jumpbox
  version: 0.4.0

params:
  env: acme-us-east-1-prod

  jumpbox_network:   access
  jumpbox_disk_pool: big-and-cheap
  jumpbox_vm_type:   medium
```

# Caveats

Jumpbox deployments cannot be updated by BOSH while people are
logged in.  The jumpbox BOSH release made a conscious decision not
to implement a drain script that terminated user sessions, in
order to avoid inconveniencing operators and risking data loss.

# History

Version 0.4.0 was the first version to support Genesis 2.6 hooks
for addon scripts and `genesis info`.

Up through version 0.3.4 of this kit, there was a subkit / feature
called `shield` which colocated the SHIELD agent for performing
local backups of the consul cluster.  As of version 0.4.0, this
model is no longer supported; operators are encouraged to use BOSH
runtime configs to colocate addon jobs instead.
