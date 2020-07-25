# Changelog

## v2

First bugfix, first new feature and first technical improvement.

### New Features
* Add `cleanup_maneuver_nodes` option. Enabled by default, this will delete any maneuver nodes created if any problem occurs when creating the transfer, in order to leave a clean slate for the next attempt.

### Bug Fixes
* Fix issue [`search.ks fails when time:seconds > 2^31`](https://github.com/maneatingape/rsvp/issues/4)
    The kOS `range` expression expects values to fit within a signed 32 bit integer. This caused the script to break when run on save games with a universal time greater than 2^31 seconds, or about 233 years. Replaced the `range` expression with a `from` loop as a straightforward workaround.

### Technical improvements
* Calculate the time at destination periapsis (used when creating the arrival node) directly from Keplerian orbital parameters of the intercept patch. This is more efficient and accurate than the previous approach, which used a line search to find the closest approach distance by trying different times.

## v1

Initial public release.