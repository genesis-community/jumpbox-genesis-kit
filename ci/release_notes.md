# Improvements

* Genesis 2.7.x support

  * Genesis now supports key usage, and has much better validation services,
    so the bespoke hooks/check has been replaced with the kit.yml for
    specifying the secrets.

  * Add customizable CA and regular X509 certificate validity periods using
    `params.ca_validity_period` and `params.cert_validity_period`

