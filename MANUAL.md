# Jumpbox Genesis Kit Manual

The **Jumpbox Genesis Kit** deploys a VM, with persistent users,
that can be used as a starting point for connecting to internal
VPC/VPN infrastructure inside the cloud.

The jumpbox contains a multitude of utilities useful for managing
and interacting with BOSH, Cloud Foundry, Concourse, and other
related components.

## Table of Contents

- [Base Parameters](#base-parameters)
- [Deployment Parameters](#deployment-parameters)
- [Cloud Configuration](#cloud-configuration)
- [Available Features](#available-features)
- [User Management](#user-management)
- [IaaS Configuration](#iaas-support)
  - [AWS Configuration](#aws-configuration)
  - [vSphere Configuration](#vsphere-configuration)
  - [OpenStack Configuration](#openstack-configuration)
  - [STACKIT Configuration](#stackit-configuration)
- [Available Addons](#available-addons)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Caveats](#caveats)
- [History](#history)

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

  You can also specify the array of users in a separate YAML file,
  and specify the `users_file` parameter to specify the name of that
  file, relative to the directory containing the environment file.
  These two methods can be used together, but if doing so, ensure the
  `users` parameter has as its first entry a `- ((append))` array
  operator.

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

# Cloud Configuration

By default, this kit uses the following VM types/networks/disk pools from your
Cloud Config. Feel free to override them in your environment, if you would
rather they use entities already existing in your Cloud Foundry:

```
params:
  jumpbox_network:   jumpbox
  jumpbox_disk_pool: jumpbox # should be at least 50GB
  jumpbox_vm_type:   jumpbox # VMs should have at least 1 CPU, and 2GB of memory
```

# Available Features

- `dev-tools` - By default, the developer build tools such as compilers and
  software development utilities (see [here](https://github.com/cloudfoundry/bosh-linux-stemcell-builder/blob/master/stemcell_builder/stages/dev_tools_config/assets/generate_dev_tools_file_list.sh) for list)
  won't be included on the jumpbox for security reasons.  If you'd like to
  have these included, use this feature.

- `bastion` - Dual-home a jumpbox, turning it into a _bastion_
  host that straddles two networks.

  Activating this feature also activates the following parameters:

  - `inside_network` - The name of the network to add a secondary,
    inside network interface.  This paremeter is **required**.

- `openvpn` - Provides an OpenVPN server, giving users access to
  the internal infrastructure without requiring an SSH session.
  Instead, users will be issued an X.509 identity certificate which
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

  - `vpn_dns_servers` - A list of DNS servers that will be advertised
    to connecting VPN clients.  Most VPN client software will set
    these as the canonical system name resolvers while the VPN is
    connected.

  - `vpn_dns_search_domains` - A list of DNS search domains that will
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
  
  - `vpn_iptables_forward` - iptables rules required for VPN traffic
    to flow properly. Automatically generated via `genesis new` however
    these can be modified or added to.

  - `vpn_external_ip` - External IP to set in the ovpn config for client
    access. Defaults to the IP address of the jumpbox but can be overridden
    if VPN traffic is routed via another address to the jumpbox.

  - `vpn_protocol` - Protocol to be used for VPN connections (`i.e. udp or tcp`).

  - `vpn_external_port` - Port to set in the ovpn config for client access.
    Defaults to 443 but can be overridden similar to the above IP parameter.

  - `vpn_compress` - Compression algorithm to be used for VPN connections (`i.e. auto, lzo, lz4, lz4-v2`).

  - `vpn_extra_configs` - List of additional OpenVPN server configuration options.

  - `vpn_extra_client_configs` - List of additional OpenVPN client configuration options.

- `wireguard` - Provides a WireGuard VPN endpoint on the jumpbox.
  Unlike OpenVPN, WireGuard uses base64 Curve25519 keypairs instead
  of X.509 certificates; peers (clients) are managed through
  vault-backed addons and take effect on redeploy via `wg syncconf`,
  which never interrupts established sessions.

  Requires an `ubuntu-noble` stemcell (the wireguard BOSH release
  depends on the in-kernel WireGuard module).

  The `openvpn` and `wireguard` features may be enabled together;
  the kit merges their iptables FORWARD/POSTROUTING rules when both
  are active.

  Activating this feature also activates the following parameters:

  - `wireguard_cidr` - Tunnel network for clients, in CIDR notation.
    Defaults to `10.20.31.0/24` (distinct from OpenVPN's default
    `172.31.255.0/24` so both VPNs can coexist).

  - `wireguard_server_address` - The server's in-tunnel address CIDR.
    Defaults to `10.20.31.1/24`; keep it the `.1` of `wireguard_cidr`.

  - `wireguard_interface` - Interface name.  Defaults to `wg0`.

  - `wireguard_port` - UDP listen port.  Defaults to `51820`.  This
    port must be reachable from clients (security group or firewall
    rule — the kit opens nothing for you).

  - `wireguard_endpoint` - Public host or host:port clients dial.
    Falls back to the jumpbox VM's IP when unset.

  - `wireguard_routed_networks` - Networks advertised to clients
    (AllowedIPs in generated client configs), in CIDR notation.

  - `wireguard_dns` - DNS servers written into generated client
    configs.

  - `wireguard_iptables_forward` - iptables FORWARD rules required
    for WireGuard traffic to flow.  Automatically generated via
    `genesis new`, but can be modified or added to.

# User Management

The Jumpbox Genesis Kit provides flexible options for managing users.

## Defining Users in Deployment

Users can be defined in two ways:

1. **Directly in the environment file** using the `users` parameter
2. **In a separate file** using the `users_file` parameter
3. **A combination of both** using the append operator

### Directly in Environment File

```yaml
params:
  users:
    - name: jsmith
      shell: /bin/bash
      ssh_keys:
        - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...
    - name: auser
      shell: /bin/zsh
      ssh_keys:
        - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...
```

### Using a Separate Users File

1. Create a dedicated users file (e.g., `users.yml`):

```yaml
users:
  - name: jsmith
    shell: /bin/bash
    ssh_keys:
      - (( append ))
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...
  - name: auser
    shell: /bin/zsh
    ssh_keys:
      - (( append ))
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...
```

2. Reference this file in your environment:

```yaml
params:
  users_file: users.yml
```

### Using Both Approaches Together

```yaml
params:
  users_file: users.yml
  users:
    - (( append ))
    - name: additional_user
      shell: /bin/bash
      ssh_keys:
        - ssh-rsa AAAAB3Nza...
```

## Managing Users with the `users` Addon

The Jumpbox Genesis Kit provides a powerful `users` addon for dynamically 
managing users and their SSH keys from various sources.

### Adding Users

```bash
# Add a user's SSH keys from GitHub (default source)
genesis do my-env -- users add username

# Add a user's SSH keys from GitLab
genesis do my-env -- users add gitlab/username

# Add keys from a local public key file
genesis do my-env -- users add /path/to/username.pub

# Add keys from a directory containing public key files
genesis do my-env -- users add /path/to/keys/directory/
```

### Removing Users

```bash
# Remove a user
genesis do my-env -- users remove username
```

### Key Source Options

- **GitHub**: Default source, fetches from `https://github.com/username.keys`
- **GitLab**: Fetches from `https://gitlab.com/username.keys`
- **Local .pub file**: Reads from a local public key file (username derived from filename)
- **Directory**: Processes all .pub files in a directory

The `users` addon creates and maintains an `ops/users.yml` file that is automatically
used in your deployment.

For more details on user management, see the [User Management documentation](docs/user-management.md).

# IaaS Support

This kit supports the following Infrastructure-as-a-Service providers:

- Amazon Web Services (AWS)
- VMware vSphere
- OpenStack
- STACKIT

## STACKIT Configuration

STACKIT is supported as an IaaS provider, with configuration similar to OpenStack. When
deploying to STACKIT, keep in mind that STACKIT has a 1:1 correspondence of networks to
subnets, unlike OpenStack which may have a single overarching network with multiple subnets.

### Cloud Config Requirements

For STACKIT deployments, you need a cloud config with appropriate VM types, disk types,
and network configuration:

```yaml
# VM types
vm_types:
- name: jumpbox
  cloud_properties:
    instance_type: m1.medium
    security_groups: [default, jumpbox]

# Disk types
disk_types:
- name: jumpbox
  disk_size: 50_000
  cloud_properties:
    type: storage_standard

# Networks
networks:
- name: jumpbox
  type: manual
  subnets:
  - range: 10.10.10.0/24
    gateway: 10.10.10.1
    dns: [8.8.8.8]
    cloud_properties:
      net_id: YOUR_NETWORK_ID
      security_groups: [default, jumpbox]
```

### Instance Types

The default values for STACKIT are:

- Instance types: 
  - `m1.small` (1 vCPU, 2GB RAM)
  - `m1.medium` (2 vCPU, 4GB RAM - recommended for jumpbox)
  - `m1.large` (4 vCPU, 8GB RAM)

### Storage Types

- Default: `storage_standard`
- High-performance: `storage_highiops`

### Network Configuration

Network configuration requires both `net_id` and `security_groups`:

```yaml
cloud_properties:
  net_id: YOUR_NETWORK_ID
  security_groups: ['default']
```

### Security Group Requirements

At minimum, your security groups should allow:
- SSH access (port 22) for management
- HTTPS access (port 443) if using OpenVPN

For detailed STACKIT configuration, see the [STACKIT Configuration Guide](docs/iaas-configurations/stackit.md).

# Available Addons

## Core Addons

- `inventory` - Run the inventory errand against the deployment.
  ```
  genesis do my-env -- inventory
  ```

- `ssh` - SSH into the jumpbox interactively.
  ```
  genesis do my-env -- ssh
  ```

- `who` - SSH into the jumpbox and determine who is logged in.
  ```
  genesis do my-env -- who
  ```

- `users` - Manage user accounts and SSH keys from various sources.
  ```
  # Add users
  genesis do my-env -- users add github/username
  genesis do my-env -- users add gitlab/username
  genesis do my-env -- users add /path/to/key.pub
  genesis do my-env -- users add /path/to/keys/dir/
  
  # Remove users
  genesis do my-env -- users remove username
  ```

## OpenVPN Addons

If the `openvpn` feature is enabled, the following addons are also available:

- `certs` - List all the X.509 VPN certificates for the users registered on 
  this jumpbox.
  ```
  genesis do my-env -- certs
  ```

- `issue-cert <user>` - Issue an X.509 certificate to a user, so that they
  can connect and authenticate to the VPN.
  ```
  genesis do my-env -- issue-cert username
  ```

- `revoke-cert <user>` - Revoke an issued X.509 VPN certificate.
  ```
  genesis do my-env -- revoke-cert username
  ```

- `renew-cert <user>` - Renew the lifetime of an existing X.509 VPN
  certificate, without changing the key that the user has.
  ```
  genesis do my-env -- renew-cert username
  ```

- `renew-all-certs` - Renew the lifetime of all existing X.509 VPN
  certificates, without changing the keys.
  ```
  genesis do my-env -- renew-all-certs
  ```

- `reissue-cert <user>` - Reissue an X.509 VPN certificate, and
  generate a new key in the process. This is useful if, for
  example, a key has been lost or compromised. The old
  certificate will be revoked.
  ```
  genesis do my-env -- reissue-cert username
  ```
  
- `generate-vpn-config <user>` - Generate a client certificate
  (if missing) and a new (or updated) openvpn config file for a 
  given user.
  ```
  genesis do my-env -- generate-vpn-config username
  ```

## WireGuard Addons

If the `wireguard` feature is enabled, the following addons are also available:

- `add-peer <name> [extra-allowed-cidr ...]` (alias `ap`) - Register a
  new WireGuard peer: generates a keypair and preshared key, allocates
  the lowest free tunnel address, and stores everything in vault.  The
  peer becomes active on the next deploy.
  ```
  genesis do my-env -- add-peer laptop
  ```

- `remove-peer <name>` (alias `rp`) - Revoke a peer.  Its registry
  entry moves to the `revoked/` archive and the next deploy drops it
  from the interface.
  ```
  genesis do my-env -- remove-peer laptop
  ```

- `list-peers` (alias `lp`) - List registered peers with their tunnel
  addresses and allowed IPs.
  ```
  genesis do my-env -- list-peers
  ```

- `generate-wg-config [-q] <name>` (alias `gw`) - Emit a wg-quick
  client configuration for a registered peer.  With `-q`, also render
  it as a terminal QR code (requires `qrencode`) for direct import
  into mobile clients.
  ```
  genesis do my-env -- generate-wg-config laptop
  ```

For detailed information on addon commands, see the [Addon Commands documentation](docs/addons.md).

# Examples

To use custom cloud config types:

```
---
kit:
  name:    jumpbox
  version: 0.4.0

genesis:
  env: acme-us-east-1-prod

params:
  jumpbox_network:   access
  jumpbox_disk_pool: big-and-cheap
  jumpbox_vm_type:   medium
```

# Troubleshooting

## Common Issues

### Deployment Fails with User-Related Errors

If your deployment fails with errors related to users:

1. Verify that your `users` parameter or `users_file` is correctly formatted
2. Check for duplicate usernames
3. Ensure SSH keys are valid and properly formatted

### OpenVPN Connection Issues

If users cannot connect to the VPN:

1. Verify that the OpenVPN service is running on the jumpbox
2. Check that security groups allow traffic on port 443 (or your configured VPN port)
3. Ensure users have valid certificates
4. Review the OpenVPN server logs for errors

### SSH Access Issues

If users cannot SSH into the jumpbox:

1. Verify that their SSH keys are correctly added to the deployment
2. Check that security groups allow SSH access (port 22)
3. Ensure network connectivity to the jumpbox

## Resolving BOSH Deployment Lock Issues

If your jumpbox deployment is locked and cannot be updated:

1. Check if any users are currently logged in:
   ```
   genesis do my-env -- who
   ```

2. If necessary, notify users and wait for them to log out before
   attempting the deployment again. The jumpbox BOSH release does
   not forcibly terminate user sessions during updates.

For more troubleshooting guidance, see the [Troubleshooting Guide](docs/troubleshooting.md).

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