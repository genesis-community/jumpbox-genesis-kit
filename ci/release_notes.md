# Improvements

* Genesis 2.7.x support

  * Genesis now supports key usage, and has much better validation services,
    so the bespoke hooks/check has been replaced with the kit.yml for
    specifying the secrets.

  * Add customizable CA and regular X509 certificate validity periods using
    `params.ca_validity_period` and `params.cert_validity_period`

# Bug Fixes

* Fixed global properties deprecation warnings.

# Software Updates

* jumpbox to [v4.7.3](https://github.com/cloudfoundry-community/jumpbox-boshrelease/releases)
* toolbelt to [v3.5.0](https://github.com/cloudfoundry-community/toolbelt-boshrelease/releases/tag/v3.5.0)
* openVPN to [v5.5.0](https://github.com/dpb587/openvpn-bosh-release/releases/tag/v5.5.0)

