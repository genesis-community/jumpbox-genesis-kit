# Improvements

- OpenVPN server-side configuration is now more configurable.
  For example, you can now choose UDP (vs. TCP), enable
  compression, and pass in arbitrary `openvpn` server and client
  configuration flags / options.

- The OpenVPN configuration created by the `generate-vpn-config`
  no longer includes the (deprecated) `keysize` configuration
  value, which makes Tunnelblick happier and less annoying.
