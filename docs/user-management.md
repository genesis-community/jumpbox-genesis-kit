# User Management in Jumpbox Genesis Kit

This document explains how to manage users in the Jumpbox Genesis Kit.

## Table of Contents

- [Overview](#overview)
- [Defining Users in Deployment Manifests](#defining-users-in-deployment-manifests)
  - [Basic User Definition](#basic-user-definition)
  - [Using a Separate Users File](#using-a-separate-users-file)
- [Managing Users with the `users` Addon](#managing-users-with-the-users-addon)
  - [Adding Users](#adding-users)
  - [Removing Users](#removing-users)
  - [Key Source Options](#key-source-options)
- [Examples](#examples)
  - [Adding Users from GitHub](#adding-users-from-github)
  - [Adding Users from GitLab](#adding-users-from-gitlab)
  - [Adding Users from Local Public Key Files](#adding-users-from-local-public-key-files)
  - [Adding Users from a Directory of Public Keys](#adding-users-from-a-directory-of-public-keys)
  - [Removing Users](#removing-users-example)
- [Technical Details](#technical-details)
  - [The `ops/users.yml` File Structure](#the-opsusersyml-file-structure)
  - [Username Requirements](#username-requirements)
  - [SSH Key Validation](#ssh-key-validation)

## Overview

The Jumpbox Genesis Kit provides robust user management capabilities that allow you to:

1. Define users directly in your deployment manifest
2. Maintain users in a separate YAML file
3. Dynamically manage users with the `users` addon
4. Import SSH keys from multiple sources (GitHub, GitLab, local files)

## Defining Users in Deployment Manifests

### Basic User Definition

You can define users directly in your environment file using the `users` parameter:

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

For better maintainability, you can define users in a separate file:

1. Create a file (e.g., `users.yml`) with your user definitions:

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

2. Reference this file in your environment file:

```yaml
params:
  users_file: users.yml
```

3. Alternatively, you can use both approaches together:

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

The `users` addon allows you to dynamically manage users by fetching SSH keys from various sources and updating the `ops/users.yml` file.

### Adding Users

To add users:

```bash
# Basic syntax
genesis do <env> -- users add <username>

# Examples
genesis do my-env -- users add jsmith                 # Add GitHub user
genesis do my-env -- users add github/jsmith          # Explicitly specify GitHub
genesis do my-env -- users add gitlab/jsmith          # Add GitLab user
genesis do my-env -- users add ./keys/jsmith.pub      # Add from local public key file
genesis do my-env -- users add /path/to/keys/dir/     # Add all users from a directory of .pub files
```

### Removing Users

To remove users:

```bash
# Basic syntax
genesis do <env> -- users remove <username>

# Examples
genesis do my-env -- users remove jsmith              # Remove a user
genesis do my-env -- users remove gitlab/jsmith       # Remove a user (source prefix is ignored)
```

### Key Source Options

The `users` addon supports multiple sources for SSH keys:

- **GitHub** (default if no source specified): fetches keys from `https://github.com/<username>.keys`
- **GitLab**: fetches keys from `https://gitlab.com/<username>.keys`
- **Local files**: reads keys from local `.pub` files
- **Directories**: processes all `.pub` files in a directory

## Examples

### Adding Users from GitHub

```bash
# Default source is GitHub
genesis do my-env -- users add jsmith

# Explicitly specify GitHub
genesis do my-env -- users add github/jsmith
```

This fetches SSH keys from `https://github.com/jsmith.keys` and adds them to the `ops/users.yml` file.

### Adding Users from GitLab

```bash
genesis do my-env -- users add gitlab/jsmith
```

This fetches SSH keys from `https://gitlab.com/jsmith.keys` and adds them to the `ops/users.yml` file.

### Adding Users from Local Public Key Files

```bash
genesis do my-env -- users add ./keys/jsmith.pub
```

This reads the SSH key from the local file `./keys/jsmith.pub` and adds it for user `jsmith` in the `ops/users.yml` file. The username is derived from the filename (without the `.pub` extension).

### Adding Users from a Directory of Public Keys

```bash
genesis do my-env -- users add ./team-keys-dir/
```

This processes all `.pub` files in the `./team-keys-dir/` directory and adds each user with their respective keys. For example, a file named `jsmith.pub` will add keys for user `jsmith`.

### Removing Users Example

```bash
genesis do my-env -- users remove jsmith
```

This removes the user `jsmith` from the `ops/users.yml` file.

## Technical Details

### The `ops/users.yml` File Structure

The `users` addon maintains user information in the `ops/users.yml` file with the following structure:

```yaml
---
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

The `(( append ))` directive ensures that keys are appended to any existing keys if the user already exists.

### Username Requirements

Usernames must:

- Be between 1 and 39 characters long
- Start with an alphanumeric character
- Contain only alphanumeric characters and hyphens
- Not have consecutive hyphens
- Not start or end with a hyphen

### SSH Key Validation

The addon validates SSH keys to ensure they are in the correct format. Supported key types include:

- RSA (`ssh-rsa`)
- DSA (`ssh-dss`)
- Ed25519 (`ssh-ed25519`)
- ECDSA (`ecdsa-sha2-nistp256`, `ecdsa-sha2-nistp384`, `ecdsa-sha2-nistp521`)

Keys must include the key type, the base64-encoded key, and optionally a comment.