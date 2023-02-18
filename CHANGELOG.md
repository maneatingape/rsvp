# Changelog

## v9

### Bug Fixes
* Support kOS 1.4.0.0 by renaming local variables to avoid conflict with built-in names.

### New Features
* The restriction on running the script when the craft is not in a stable orbit has been relaxed, so that finding future transfer times can happen when on the ground. Maneuver nodes can still only be created when the craft is in a stable orbit.

## v8

### Bug Fixes
* Add a safety check that the predicted insertion velocity at the boundary of the destination's SOI is above the minimum possible (based on the desired final periapsis). This is similar to the existing check that the ejection velocity from the origin is greater than the minimum possible. This prevents an error occuring during transfer refinement in some scenarios when the initial raw point-to-point Lambert solution predicts an intercept velocity less than this minimum.

## v7

### New Features
This release increases the speed of the hill climbing algorithm when searching the pork chop plot in certain scenarios. The larger the relative difference between the origin and destination orbits, the more benefit this provides. The eventual transfer found and delta-v needed is the same as before but takes less time to find.

For example a transfer search from Kerbin to Duna takes the same time. A transfer search from Moho to Eeloo takes 15% of the previous time.

### Technical Improvements
* When verbose mode is enabled, print details if a problem occurs during a transfer search. 
* Add CPU speed boost to quickstart code snippet

## v6

### New Features

This release adds a new mathematical approach to refining transfers when the ratio of the destination SOI to Periapsis exceeds a threshold. This fixes 2 issues:
* Transfers to larger moons (especially in the Jool system) are much less likely to go astray.
* Polar orbit orientation when travelling to Mun or Ike no longer results in huge delta-v values.

The new approach is based on the paper [A new method of patched-conic for interplanetary orbit](https://doi.org/10.1016/j.ijleo.2017.10.153) by Jin Li, Jianhui Zhao and Fan Li.

Given a velocity vector at SOI boundary, periapsis altitude and inclination, this approach calculates the position vector that satisifies these contraints. This position vector is combined in a feedback loop with the Lambert solver to refine the initial estimate from one that only considers planets as points to one that takes the SOI spheres into account. This removes the need both for the `impact_parameter` function and the line search algorithm simplifying the vessel-to-body case. The body-to-body case also simplifies into a single step instead of two.

For vessels and planets with a SOI to Periapsis ratio of less than 1% the existing strategy is used. This strategy considers the planets as a zero-width point on the assumption that over large distance only small adjustments will be need to the predicted transfer.

However some bodies in KSP have extremely large SOI to Periapsis ratios, for example Ike (38%), Mun (23%) and Tylo (17%). For transfers to and from these bodies, the SOI sphere needs to be taken into account when finding the lowest cost transfer. The `offset_from_soi_edge` and `duration_from_soi_edge` function in `orbit.ks` predict the time and position where a craft will exit/enter SOI.

Interestingly another challenge with very large SOI to Periapsis ratios is that the minimum escape velocity can be higher than the desired transfer. For example a direct Hohmann transfer from Laythe to Vall is impossible, as the minmum escape velocity from Laythe is *higher* than the velocity required. The search algorithm now supports a minimum value for deltav, making this type of transfer possible.

### Bug Fixes
* Fix calculation of periapis time when insertion orbit is mathematically elliptical. Insertion manuever node will now be placed in the correct location.
* Fix bug in a guard clause in the Lambert solver that was throwing `NaN` exception is certain situations.

### Technical Improvements
* Add validation check to `final_orbit_periapsis` option to ensure that supplied value is within SOI radius of destination.
* Refactor maneuver related code from `orbit.ks` to `maneuver.ks`.

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