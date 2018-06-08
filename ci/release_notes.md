# Improvements

The Jumpbox Genesis Kit now makes use of the substantial improvements
introduced in Genesis v2.6.0+, notably kit hooks that provide better environment
creation, deployment and checks, as well as info and add-ons that allow you to
manage your environments after deployment.

Existing environments should be able to update to this version without any
undue stress of churn, but a few "refreshes" are desirable.

    The `shield` subkit is gone; it is now recommended that you use BOSH
    runtime configuration add-ons to add the Shield agent to your deployments.

    The `proxy` subkit is now gone. If you specify proxy parameters, they will
    be honored. If you don't they default to "no proxy in effect".

    The `azure` subkit is now gone, as it only provided changes to availability
    zones and set, which don't make any impact to single-instance environments.

