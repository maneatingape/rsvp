# Changelog

## v5

### Bug Fixes
* Fix issue [`Tried to push NAN into the stack when attempting an intercept from a nearly-approaching orbit`](https://github.com/maneatingape/rsvp/issues/6). This was preventing a craft that had just missed an intercept from correcting its orbit. The root cause was slight numeric inaccuracies in the Lambert solver for certain time of flight calculations resulting in an attempt to take the log of a negative number. Added a guard to protect against this edge case.

### Technical Improvements
* Add `build_documentation` [Github Action](https://github.com/features/actions) that creates documentation in the same format as kOS. On any change to the `doc` folder, this action will automatically run the [Sphinx generator](https://www.sphinx-doc.org/en/master/) to convert raw `.rst` text files to HTML, then publish the changes to Github Pages. This keeps a clean separation in the repository between the raw source files and the generated output.

## v4

Support `.ksm` compiled files.

### New Features
* Implement issue [`Running other files should not include extension`](https://github.com/maneatingape/rsvp/issues/5). Add ability to use more compact compiled version of the source on craft that have limited volume space. Compiled files take about 20% of the space of the raw source, resulting in a significant space savings.
* Add `compile_to` convenience function that compiles the source to a user-specified destination, for example a kOS processor hard drive.

## v3

Improve handling of objects on hyperbolic orbits.

### Technical Improvements
* Use different strategy when calculating default `search_duration`, `max_time_of_flight` and `search_interval` values for a destination with a hyperbolic orbit, for example an asteroid or comet. This change prevents a `Tried to push Infinity onto the stack` error that occurred because the approach used for planets assumes an elliptical orbit with a finite orbital period.

## v2

First bugfix, first new feature and first technical improvement.

### New Features
* Add `cleanup_maneuver_nodes` option. Enabled by default, this will delete any maneuver nodes created if any problem occurs when creating the transfer, in order to leave a clean slate for the next attempt.

### Bug Fixes
* Fix issue [`search.ks fails when time:seconds > 2^31`](https://github.com/maneatingape/rsvp/issues/4). The kOS `range` expression expects values to fit within a signed 32 bit integer. This caused the script to break when run on save games with a universal time greater than 2³¹ seconds or about 233 years. Replaced the `range` expression with a `from` loop as a straightforward workaround.

### Technical Improvements
* Calculate the time at destination periapsis (used when creating the arrival node) directly from Keplerian orbital parameters of the intercept patch. This is more efficient and accurate than the previous approach, which used a line search to find the closest approach distance by trying different times.

## v1

Initial public release.