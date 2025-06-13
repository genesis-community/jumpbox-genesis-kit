# Jumpbox Genesis Kit Troubleshooting Guide

This document provides solutions to common issues you might encounter when deploying and managing a jumpbox with the Jumpbox Genesis Kit.

## Table of Contents

- [Deployment Issues](#deployment-issues)
  - [Deployment Fails Due to User Management](#deployment-fails-due-to-user-management)
  - [Deployment Is Locked](#deployment-is-locked)
  - [Cloud Config Mismatch](#cloud-config-mismatch)
- [SSH Access Issues](#ssh-access-issues)
  - [Cannot SSH into Jumpbox](#cannot-ssh-into-jumpbox)
  - [SSH Keys Not Working](#ssh-keys-not-working)
- [OpenVPN Issues](#openvpn-issues)
  - [Certificate Generation Failures](#certificate-generation-failures)
  - [VPN Connection Issues](#vpn-connection-issues)
  - [VPN Routing Issues](#vpn-routing-issues)
- [User Management Issues](#user-management-issues)
  - [Cannot Add Users](#cannot-add-users)
  - [Cannot Fetch Keys from GitHub/GitLab](#cannot-fetch-keys-from-githubgitlab)
  - [Invalid Public Key Format](#invalid-public-key-format)
- [IaaS-Specific Issues](#iaas-specific-issues)
  - [AWS Issues](#aws-issues)
  - [vSphere Issues](#vsphere-issues)
  - [OpenStack Issues](#openstack-issues)
  - [STACKIT Issues](#stackit-issues)

## Deployment Issues

### Deployment Fails Due to User Management

**Symptoms:**
- BOSH deployment fails with errors related to user configuration
- Error messages mention missing or invalid SSH keys

**Solutions:**
1. Verify the format of your `users` parameter or `users_file` content:
   ```yaml
   users:
     - name: username
       shell: /bin/bash
       ssh_keys:
         - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...
   ```

2. Ensure SSH keys are correctly formatted and complete 

3. Check for duplicate usernames in your configuration

4. If using both `users_file` and `users` parameter, ensure you have the `(( append ))` operator:
   ```yaml
   params:
     users_file: users.yml
     users:
       - (( append ))
       - name: additional_user
         # ...
   ```

### Deployment Is Locked

**Symptoms:**
- BOSH deployment fails with "deployment is locked" error message
- Deployment appears to hang during update

**Solutions:**
1. Check if users are currently logged into the jumpbox:
   ```bash
   genesis do <env> -- who
   ```

2. Ask users to log out before attempting the deployment again

3. If absolutely necessary and no critical work is being done, you can force a BOSH deploy with `--recreate` and `--fix`, but this will terminate all user sessions:
   ```bash
   BOSH_NON_INTERACTIVE=yes bosh -d <deployment-name> deploy --recreate --fix <manifest-path>
   ```

### Cloud Config Mismatch

**Symptoms:**
- Error messages about missing VM types, disk types, or networks
- "Instance group 'jumpbox' references an unknown vm type" errors

**Solutions:**
1. Verify your cloud config has the required elements:
   ```bash
   bosh cloud-config
   ```

2. Add missing elements to your cloud config or override the defaults in your deployment:
   ```yaml
   params:
     jumpbox_network: custom-network
     jumpbox_vm_type: custom-vm-type
     jumpbox_disk_pool: custom-disk-pool
   ```

3. Check for typos in network, VM type, or disk pool names

## SSH Access Issues

### Cannot SSH into Jumpbox

**Symptoms:**
- SSH connection timeout
- Connection refused errors
- Authentication errors

**Solutions:**
1. Verify the jumpbox VM is running:
   ```bash
   bosh -d <deployment-name> instances
   ```

2. Check that the security group allows SSH access (port 22)

3. Verify the network connectivity to the jumpbox's IP address:
   ```bash
   ping <jumpbox-ip>
   ```

4. Try using the SSH addon command which uses BOSH SSH:
   ```bash
   genesis do <env> -- ssh
   ```

### SSH Keys Not Working

**Symptoms:**
- Permission denied (publickey) errors when trying to SSH
- User can SSH but with incorrect permissions

**Solutions:**
1. Verify the user exists on the jumpbox:
   ```bash
   bosh -d <deployment-name> ssh jumpbox/0 -c "grep <username> /etc/passwd"
   ```

2. Check that the SSH key is correctly added to the user:
   ```bash
   bosh -d <deployment-name> ssh jumpbox/0 -c "cat /home/<username>/.ssh/authorized_keys"
   ```

3. Redeploy with updated SSH keys using the `users` addon:
   ```bash
   genesis do <env> -- users add <username>
   ```
   
4. Ensure you're using the correct key pair when connecting:
   ```bash
   ssh -i /path/to/private/key <username>@<jumpbox-ip>
   ```

## OpenVPN Issues

### Certificate Generation Failures

**Symptoms:**
- Certificate generation addons fail with errors
- Certificate exists but is invalid

**Solutions:**
1. Check the OpenVPN CA status:
   ```bash
   bosh -d <deployment-name> ssh jumpbox/0 -c "cd /var/vcap/jobs/openvpn/etc/openvpn/easy-rsa && ./easyrsa list-all"
   ```

2. Try reissuing the certificate:
   ```bash
   genesis do <env> -- reissue-cert <username>
   ```

3. Verify the OpenVPN service is running:
   ```bash
   bosh -d <deployment-name> ssh jumpbox/0 -c "monit summary | grep openvpn"
   ```

### VPN Connection Issues

**Symptoms:**
- Cannot connect to VPN server
- VPN connection drops frequently
- TLS handshake failures

**Solutions:**
1. Verify the OpenVPN service is running:
   ```bash
   bosh -d <deployment-name> ssh jumpbox/0 -c "monit summary | grep openvpn"
   ```

2. Check that security groups allow traffic on port 443 (or your configured VPN port)

3. Verify that the `vpn_external_ip` parameter is correctly set if using a NAT or public IP

4. Check the OpenVPN logs for errors:
   ```bash
   bosh -d <deployment-name> ssh jumpbox/0 -c "cat /var/vcap/sys/log/openvpn/openvpn.log"
   ```

5. Regenerate the client configuration:
   ```bash
   genesis do <env> -- generate-vpn-config <username>
   ```

### VPN Routing Issues

**Symptoms:**
- Connected to VPN but cannot access internal resources
- DNS resolution fails over VPN
- Split tunneling not working correctly

**Solutions:**
1. Verify VPN routing configuration:
   ```yaml
   params:
     vpn_client_routes:
       - 10.0.0.0 255.255.0.0  # Routes traffic to 10.0.0.0/16 over VPN
   ```

2. Check DNS server configuration:
   ```yaml
   params:
     vpn_dns_servers:
       - 10.0.0.2
     vpn_dns_search_domains:
       - internal.example.com
   ```

3. Verify iptables rules are correctly configured:
   ```bash
   bosh -d <deployment-name> ssh jumpbox/0 -c "iptables -t nat -L -n -v"
   ```

## User Management Issues

### Cannot Add Users

**Symptoms:**
- The `users` addon fails to add new users
- Error writing to `ops/users.yml`

**Solutions:**
1. Check permissions on the `ops` directory:
   ```bash
   ls -la ops/
   ```

2. Create the directory if it doesn't exist:
   ```bash
   mkdir -p ops
   ```

3. Check the format of usernames and SSH keys:
   ```bash
   # Usernames must meet specific criteria
   # SSH keys must be valid format
   ```

### Cannot Fetch Keys from GitHub/GitLab

**Symptoms:**
- The `users` addon fails to fetch keys with network errors
- "User not found" or "Rate limit exceeded" errors

**Solutions:**
1. Verify network connectivity to GitHub/GitLab:
   ```bash
   ping github.com
   ```

2. Check if the username exists on the platform:
   ```bash
   curl https://github.com/<username>.keys
   ```

3. If rate limited, wait a few minutes before trying again

4. Consider using a local public key file instead:
   ```bash
   # Ask the user to provide their key
   genesis do <env> -- users add /path/to/username.pub
   ```

### Invalid Public Key Format

**Symptoms:**
- Error messages about invalid SSH key formats
- Keys not being accepted during deployment

**Solutions:**
1. Verify the key format is valid (should start with ssh-rsa, ssh-dss, ssh-ed25519, etc.)

2. Check for common problems like linebreaks in the key

3. Regenerate the key if necessary:
   ```bash
   ssh-keygen -t ed25519 -C "user@example.com"
   ```

## IaaS-Specific Issues

### AWS Issues

**Symptoms:**
- Deployment fails with AWS API errors
- Network connectivity issues

**Solutions:**
1. Verify AWS credentials have required permissions

2. Check that the specified VPC, subnet, and security groups exist:
   ```bash
   aws ec2 describe-vpcs
   aws ec2 describe-subnets
   aws ec2 describe-security-groups
   ```

3. Ensure security groups allow SSH access (port 22)

### vSphere Issues

**Symptoms:**
- Deployment fails with vSphere API errors
- VM cannot be created or accessed

**Solutions:**
1. Verify vSphere credentials have required permissions

2. Check resource pool and datastore availability:
   ```bash
   bosh cloud-check
   ```

3. Verify network configuration in the cloud config

### OpenStack Issues

**Symptoms:**
- Deployment fails with OpenStack API errors
- VM creation fails or timeouts

**Solutions:**
1. Verify OpenStack credentials have required permissions

2. Check that the specified networks and security groups exist:
   ```bash
   openstack network list
   openstack security group list
   ```

3. Ensure that quotas are sufficient for the deployment

### STACKIT Issues

**Symptoms:**
- Deployment fails with networking issues
- Security group configuration errors

**Solutions:**
1. Remember that STACKIT has a 1:1 relationship between networks and subnets

2. Verify the `net_id` is correctly specified:
   ```yaml
   cloud_properties:
     net_id: YOUR_NETWORK_ID
     security_groups: [default, jumpbox]
   ```

3. Check that security groups allow required traffic:
   - SSH (port 22)
   - HTTPS (port 443) if using OpenVPN

4. If using a jumpbox as a bastion, ensure proper routes are configured in your cloud config network definition