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

Once created, refer to the deployment repo's README for information on creating and managing your jumpbox deployment.

What's New
-----------

### Enhanced User Management

The kit now features robust user management capabilities:
- Add users from GitHub/GitLab SSH keys with a simple command
- Import SSH keys from local files or directories
- Dynamically manage users without modifying deployment manifests

Example: `genesis do my-env -- users add github/username`

See the [User Management documentation](docs/user-management.md) for details.

### STACKIT IaaS Support

The kit now supports STACKIT as an IaaS provider, joining the existing support for AWS, vSphere, and OpenStack. STACKIT configuration follows similar patterns to OpenStack but with specific considerations for networking and security groups.

### Refactored Addon System

The addon system has been completely refactored to use modular Perl components, improving maintainability and extensibility. All addon commands now use a consistent interface, making them easier to use and extend.

Validation
----------

This kit bundles an `inventory` errand, on the main `jumpbox`
instance, so that you can validate the installation and also get
information about the versions of things installed.  To run it:

```
bosh run-errand inventory
```

IaaS Support
-----------

This Genesis Kit supports the following Infrastructure-as-a-Service providers:

- Amazon Web Services (AWS)
- VMware vSphere
- OpenStack
- STACKIT

See the [IaaS configuration documentation](docs/iaas-configurations/) for details on each provider.

Available Features
-----------

- `dev-tools` - Include development build tools (compilers, etc.)
- `bastion` - Dual-home a jumpbox as a bastion host
- `openvpn` - Provide VPN access to internal infrastructure

Available Addons
-----------

- `inventory` - Run the inventory errand against the deployment
- `ssh` - SSH into the jumpbox (interactively)
- `who` - See who is logged in to the jumpbox
- `users` - Manage jumpbox users from various sources (GitHub, GitLab, local)

When `openvpn` is enabled:
- `certs` - List all VPN certificates
- `issue-cert` - Issue a VPN certificate to a user
- `revoke-cert` - Revoke a VPN certificate
- `renew-cert` - Renew a VPN certificate without changing the key
- `renew-all-certs` - Renew all VPN certificates
- `reissue-cert` - Reissue a VPN certificate with a new key
- `generate-vpn-config` - Generate a client certificate and configuration

See the [Addon Commands documentation](docs/addons.md) for detailed usage.

Learn More
----------

For more in-depth documentation:

- [Manual](MANUAL.md) - Complete parameter and feature reference
- [User Management](docs/user-management.md) - Detailed guide on managing users
- [IaaS Configurations](docs/iaas-configurations/) - Provider-specific configuration guides
- [Addon Commands](docs/addons.md) - Comprehensive guide to all addon commands

[1]: https://github.com/cloudfoundry-community/jumpbox-boshrelease
[2]: https://github.com/cloudfoundry-community/openvpn-boshrelease
[3]: MANUAL.md