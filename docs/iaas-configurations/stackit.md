# STACKIT IaaS Configuration Guide

This document provides detailed information on deploying the Jumpbox Genesis Kit on STACKIT infrastructure.

## Table of Contents

- [Overview](#overview)
- [STACKIT-Specific Considerations](#stackit-specific-considerations)
  - [Network-Subnet Relationship](#network-subnet-relationship)
  - [Security Groups](#security-groups)
- [Configuration](#configuration)
  - [Cloud Config](#cloud-config)
  - [Instance Types](#instance-types)
  - [Storage Types](#storage-types)
  - [Network Configuration](#network-configuration)
- [Example Deployment](#example-deployment)
  - [Basic STACKIT Deployment](#basic-stackit-deployment)
  - [STACKIT Deployment with OpenVPN](#stackit-deployment-with-openvpn)
- [Troubleshooting](#troubleshooting)

## Overview

STACKIT is a European cloud provider offering Infrastructure-as-a-Service (IaaS) capabilities. The Jumpbox Genesis Kit supports deploying jumpbox VMs on STACKIT infrastructure.

## STACKIT-Specific Considerations

### Network-Subnet Relationship

Unlike some other OpenStack-based providers, STACKIT has a 1:1 correspondence between networks and subnets. This means that each network you create will have exactly one subnet associated with it. This is different from traditional OpenStack deployments where a single network might have multiple subnets.

### Security Groups

STACKIT requires explicit security group configuration to allow network traffic to your jumpbox. At minimum, you should allow:

- SSH (port 22)
- HTTPS (port 443) if using OpenVPN
- Any other ports required by your specific use case

## Configuration

### Cloud Config

For STACKIT deployments, you'll need a BOSH cloud config that includes appropriate VM types, disk types, and networks. Here's an example of the required sections:

```yaml
# Example cloud-config for STACKIT

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

STACKIT provides several VM instance types. The default types used by the Jumpbox Genesis Kit are:

- **m1.small**: 1 vCPU, 2GB RAM
- **m1.medium**: 2 vCPU, 4GB RAM (default for jumpbox)
- **m1.large**: 4 vCPU, 8GB RAM

Other available instance types:

- **m1.xlarge**: 8 vCPU, 16GB RAM
- **m1.2xlarge**: 16 vCPU, 32GB RAM
- **m1.4xlarge**: 32 vCPU, 64GB RAM

Choose an instance type based on your performance needs. For most jumpbox deployments, `m1.medium` is sufficient.

### Storage Types

STACKIT supports multiple storage types:

- **storage_standard**: Standard storage (default)
- **storage_highiops**: High IOPS storage for better performance

For jumpbox deployments, the standard storage type is usually adequate.

### Network Configuration

When configuring networks in STACKIT, you need to provide:

1. **Network ID**: The ID of the network you created in STACKIT
2. **Security Groups**: The security groups to apply to the network interfaces

Example network configuration:

```yaml
cloud_properties:
  net_id: YOUR_NETWORK_ID
  security_groups: [default, jumpbox]
```

## Example Deployment

### Basic STACKIT Deployment

Here's a basic example of a jumpbox deployment on STACKIT:

```yaml
---
kit:
  name: jumpbox
  version: latest

genesis:
  env: stackit-eu-prod
  
params:
  hostname: stackit-jumpbox
  
  # Network configuration
  jumpbox_network: jumpbox
  jumpbox_vm_type: jumpbox
  jumpbox_disk_pool: jumpbox
  
  # Users
  users:
    - name: admin
      shell: /bin/bash
      ssh_keys:
        - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...
```

### STACKIT Deployment with OpenVPN

Here's an example with OpenVPN enabled:

```yaml
---
kit:
  name: jumpbox
  version: latest

genesis:
  env: stackit-eu-prod
  
params:
  hostname: stackit-jumpbox-vpn
  
  # Network configuration
  jumpbox_network: jumpbox
  jumpbox_vm_type: jumpbox
  jumpbox_disk_pool: jumpbox
  
  # OpenVPN specific parameters
  vpn_client_routes:
    - 10.10.10.0 255.255.255.0
  vpn_dns_servers:
    - 8.8.8.8
    - 8.8.4.4
  
  # Users
  users:
    - name: admin
      shell: /bin/bash
      ssh_keys:
        - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...

features:
  - openvpn
```

## Troubleshooting

### Common Issues and Solutions

1. **Cannot connect to jumpbox**
   - Verify security groups allow SSH access (port 22)
   - Check that the jumpbox has a public IP or is accessible through your VPN

2. **OpenVPN connection fails**
   - Ensure security groups allow traffic on port 443 (or your configured VPN port)
   - Verify the `vpn_external_ip` is correctly set to a publicly accessible IP

3. **Deployment fails with network errors**
   - Confirm that the network ID (`net_id`) in your cloud config is correct
   - Verify that security groups exist and are correctly configured

4. **"No route to host" errors**
   - Check that your STACKIT router has the appropriate routes configured
   - Verify that security group rules allow traffic between necessary networks