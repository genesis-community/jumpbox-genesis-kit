# Software updates

- `jumpbox-boshrelease` is now at [v4.6.2][1]
- `toolbelt-boshrelease` is now at [v3.4.4][2]

[1]: https://github.com/cloudfoundry-community/jumpbox-boshrelease/releases/tag/v4.6.2
[2]: https://github.com/cloudfoundry-community/toolbelt-boshrelease/releases/tag/v3.4.4

# Improvements

- OpenVPN server-side configuration is now more configurable.
  For example, you can now choose UDP (vs. TCP), enable
  compression, and pass in arbitrary `openvpn` server and client
  configuration flags / options.

- The OpenVPN configuration created by the `generate-vpn-config`
  no longer includes the (deprecated) `keysize` configuration
  value, which makes Tunnelblick happier and less annoying.
