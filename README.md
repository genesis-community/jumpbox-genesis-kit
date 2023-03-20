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

Validation
----------

This kit bundles an `inventory` errand, on the main `jumpbox`
instance, so that you can validate the installation and also get
information about the versions of things installed.  To run it:

```
bosh run-errand inventory
```

Learn More
----------

For more in-depth documentation, check out the [manual][3].

[1]: https://github.com/cloudfoundry-community/jumpbox-boshrelease
[2]: https://github.com/Qarik-Group/openvpn-boshrelease
[3]: MANUAL.md
