# Jumpbox Genesis Kit Addon Commands

This document provides detailed information on all addon commands available in the Jumpbox Genesis Kit.

## Table of Contents

- [Core Addons](#core-addons)
  - [inventory](#inventory)
  - [ssh](#ssh)
  - [who](#who)
  - [users](#users)
- [OpenVPN Addons](#openvpn-addons)
  - [certs](#certs)
  - [issue-cert](#issue-cert)
  - [revoke-cert](#revoke-cert)
  - [renew-cert](#renew-cert)
  - [renew-all-certs](#renew-all-certs)
  - [reissue-cert](#reissue-cert)
  - [generate-vpn-config](#generate-vpn-config)

## Core Addons

### inventory

The `inventory` addon runs the inventory errand on the jumpbox VM, which provides information about the installed software packages and their versions.

**Usage:**

```bash
genesis do <env> -- inventory
```

**Example Output:**

```
Task 123 | 12:34:56 | Preparing deployment: Preparing deployment (00:00:01)
Task 123 | 12:34:57 | Running errand: jumpbox/0 (00:00:02)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

bosh          6.2.1
cf            7.1.0
credhub       2.8.0
genesis       2.8.0
safe          1.6.1
spruce        1.27.0
vault         1.5.0

Stderr     -

Succeeded
```

### ssh

The `ssh` addon logs you into the jumpbox. It connects as the first account in `params.users`, and you can name a different account by setting `GENESIS_JUMPBOX_USER`.

**Usage:**

```bash
genesis <env> do -- ssh
genesis <env> do -- ssh -- hostname
genesis <env> do -- ssh -L 8080:localhost:80 -- uptime -p
```

With no arguments you get an interactive shell. Anything before a `--` goes to the `ssh` command itself, so that is where options such as `-L` belong. Anything after a `--` is the command to run on the jumpbox. The addon quotes each word of it, so a word that holds spaces or quotes reaches the remote shell exactly as you typed it.

### who

The `who` addon shows the users currently logged into the jumpbox. It logs in the same way the `ssh` addon does.

**Usage:**

```bash
genesis <env> do -- who
genesis <env> do -- who -- -a
```

Anything before a `--` goes to the `ssh` command, and anything after a `--` goes to the remote `who`.

**Example Output:**

```
Task 124 | 12:45:56 | Preparing deployment: Preparing deployment (00:00:01)
Task 124 | 12:45:57 | Running errand: jumpbox/0 (00:00:01)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

jsmith   pts/0      2023-05-19 11:44    00:42    (10.0.0.5)
auser    pts/1      2023-05-19 12:15    00:10    (10.0.0.10)

Stderr     -

Succeeded
```

### users

The `users` addon provides powerful user management functionality, allowing you to add and remove users by fetching SSH keys from various sources.

**Usage:**

```bash
# Add users
genesis do <env> -- users add <username>
genesis do <env> -- users add github/<username>
genesis do <env> -- users add gitlab/<username>
genesis do <env> -- users add /path/to/key.pub
genesis do <env> -- users add /path/to/keys/directory/

# Remove users
genesis do <env> -- users remove <username>
```

**Example: Add a user from GitHub**

```bash
genesis do my-env -- users add jsmith
```

**Example Output:**

```
[info] Processing github user: jsmith
[success] Found 2 valid keys for jsmith from github

Generating YAML file...
[success] YAML file 'ops/users.yml' has been updated successfully

=== Summary ===
[info] Action performed: add
[info] Total users processed: 1
[success] Successful: 1
[error] Failed: 0
```

**Example: Add a user from GitLab**

```bash
genesis do my-env -- users add gitlab/auser
```

**Example: Add users from local public key files**

```bash
genesis do my-env -- users add ./keys/buser.pub
genesis do my-env -- users add ./team-keys-dir/
```

**Example: Remove a user**

```bash
genesis do my-env -- users remove jsmith
```

For more details on the `users` addon, see the [User Management documentation](user-management.md).

## OpenVPN Addons

The following addons are available when the `openvpn` feature is enabled.

### certs

The `certs` addon lists all X.509 VPN certificates for users registered on the jumpbox.

**Usage:**

```bash
genesis do <env> -- certs
```

**Example Output:**

```
Task 125 | 12:56:57 | Preparing deployment: Preparing deployment (00:00:01)
Task 125 | 12:56:58 | Running errand: jumpbox/0 (00:00:01)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

Certificate Name     Status      Expiration
-----------------    --------    ----------
jsmith               Valid       May 19 2024
auser                Valid       May 19 2024
buser                Revoked     -

Stderr     -

Succeeded
```

### issue-cert

The `issue-cert` addon issues an X.509 certificate to a user for VPN authentication.

**Usage:**

```bash
genesis do <env> -- issue-cert <username>
```

**Example:**

```bash
genesis do my-env -- issue-cert newuser
```

**Example Output:**

```
Task 126 | 13:01:23 | Preparing deployment: Preparing deployment (00:00:01)
Task 126 | 13:01:24 | Running errand: jumpbox/0 (00:00:03)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

Certificate for newuser has been issued
Certificate is valid until May 19 2024
Certificate file saved to /tmp/newuser.crt
Key file saved to /tmp/newuser.key

Stderr     -

Succeeded
```

### revoke-cert

The `revoke-cert` addon revokes a previously issued X.509 VPN certificate.

**Usage:**

```bash
genesis do <env> -- revoke-cert <username>
```

**Example:**

```bash
genesis do my-env -- revoke-cert olduser
```

**Example Output:**

```
Task 127 | 13:05:45 | Preparing deployment: Preparing deployment (00:00:01)
Task 127 | 13:05:46 | Running errand: jumpbox/0 (00:00:02)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

Certificate for olduser has been revoked

Stderr     -

Succeeded
```

### renew-cert

The `renew-cert` addon renews the lifetime of an existing X.509 VPN certificate, without changing the user's key.

**Usage:**

```bash
genesis do <env> -- renew-cert <username>
```

**Example:**

```bash
genesis do my-env -- renew-cert jsmith
```

**Example Output:**

```
Task 128 | 13:15:12 | Preparing deployment: Preparing deployment (00:00:01)
Task 128 | 13:15:13 | Running errand: jumpbox/0 (00:00:02)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

Certificate for jsmith has been renewed
Certificate is now valid until May 19 2024
Certificate file saved to /tmp/jsmith.crt

Stderr     -

Succeeded
```

### renew-all-certs

The `renew-all-certs` addon renews the lifetime of all existing X.509 VPN certificates, without changing any keys.

**Usage:**

```bash
genesis do <env> -- renew-all-certs
```

**Example Output:**

```
Task 129 | 13:20:45 | Preparing deployment: Preparing deployment (00:00:01)
Task 129 | 13:20:46 | Running errand: jumpbox/0 (00:00:05)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

Renewed 3 certificates:
  - jsmith
  - auser
  - newuser

All certificates now valid until May 19 2024

Stderr     -

Succeeded
```

### reissue-cert

The `reissue-cert` addon reissues an X.509 VPN certificate with a new key. This is useful if a key has been lost or compromised.

**Usage:**

```bash
genesis do <env> -- reissue-cert <username>
```

**Example:**

```bash
genesis do my-env -- reissue-cert jsmith
```

**Example Output:**

```
Task 130 | 13:30:23 | Preparing deployment: Preparing deployment (00:00:01)
Task 130 | 13:30:24 | Running errand: jumpbox/0 (00:00:04)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

Old certificate for jsmith has been revoked
New certificate for jsmith has been issued
Certificate is valid until May 19 2024
Certificate file saved to /tmp/jsmith.crt
Key file saved to /tmp/jsmith.key

Stderr     -

Succeeded
```

### generate-vpn-config

The `generate-vpn-config` addon generates a client certificate (if missing) and a new or updated OpenVPN configuration file for a given user.

**Usage:**

```bash
genesis do <env> -- generate-vpn-config <username>
```

**Example:**

```bash
genesis do my-env -- generate-vpn-config jsmith
```

**Example Output:**

```
Task 131 | 13:40:56 | Preparing deployment: Preparing deployment (00:00:01)
Task 131 | 13:40:57 | Running errand: jumpbox/0 (00:00:03)

Instance   jumpbox/a1b2c3d4-e5f6-7890-abcd-ef1234567890
Exit Code  0
Stdout     -

OpenVPN config for jsmith has been generated
Config file saved to /tmp/jsmith.ovpn

This file contains:
- Certificate information
- Private key
- OpenVPN configuration settings

Send this file to jsmith for use with their OpenVPN client

Stderr     -

Succeeded
```

## Further Information

These addon commands are implemented as modular Perl components in the `hooks/` directory of the Genesis Kit. For implementation details, you can examine the hook files directly.

For more information on the specific features and parameters referenced by these addons, refer to the [Jumpbox Genesis Kit Manual](../MANUAL.md).