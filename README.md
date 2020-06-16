# RSVP

*RSVP* is a [kOS](https://ksp-kos.github.io/KOS/) library that finds orbital [launch windows](https://en.wikipedia.org/wiki/Launch_window) in the game [Kerbal Space Program](https://www.kerbalspaceprogram.com/).
The acronym stands for "Rendezvous s’il vous plaît", a playful twist on the regular meaning.

This library enables players to make automated low delta-v transfers between two planets or vessels in-game, either directly from their own kOS scripts or from the kOS console. It provides a scriptable alternative to existing tools, such as the excellent web based [Launch Window Planner](https://alexmoon.github.io/ksp/) or the snazzy [MechJeb Maneuver Planner](https://github.com/MuMech/MechJeb2/wiki/Maneuver-Planner).

## Features

* Integrates with your kOS scripts, supporting interplanetary travel.
* Adapts to planetary packs such as [Outer Planets Mods](https://forum.kerbalspaceprogram.com/index.php?/topic/184789-131-18x-outer-planets-mod-v226-4th-feb-2020/), [RSS](https://github.com/KSP-RO/RealSolarSystem) and [JNSQ](https://github.com/Galileo88/JNSQ).
* Supports vessel to vessel rendezvous e.g. docking, rescue missions or supply runs.

## Quickstart

1. Go to the "Releases" tab then download the latest version as a zip or tar file.
2. Unpack into `<KSP install location>/Ships/Script` directory. This step adds the library to the kOS archive volume, making it available to all vessels.
3. Rename the newly created directory to `rsvp`.
3. Call the entry point from your own script:
    ```
    runoncepath("0:/rsvp/main.ks").

    // Default value is 250. Overclocking CPU speed to maximum is recommended
    // as finding transfers is computationally intensive.
    set config:ipu to 2000.

    local options is lexicon("verbose", true).
    find_launch_window(kerbin, duna, options).
    ```
This will print the time of the next transfer window from Kerbin to Duna into the console using the following defaults:
* Earliest departure time is the current universal time of the vessel.
* Departure orbit is circular at 100km altitude with 0° inclination.
* Arrival orbit is circular at 100km altitude.

## Configuration

The following options allow players to customize and tweak the desired transfer orbit. The general philosophy is that sensible defaults are provided for each option so that only custom values need to be provided. Specify options by adding them as key/value pairs to the `options` lexicon parameter.

### Verbose

Prints comprehensive details to the kOS console if set to "True".

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `verbose` | False | `Boolean` |

### Earliest Departure

When to start searching for transfer windows. Time can be in the vessel's past, present or future. The only restriction is that the time must be greater than or equal to the epoch time (Year 1, Day 1, 0:00:00)

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `earliest_departure` | Current universal time of CPU vessel | Seconds from epoch as `Scalar` or `Timespan` |

### Search Duration

Only search for transfer windows within the specified duration from earliest departure. Restricting the search duration can come in handy when time is of the essence. Increasing the duration may reveal a lower cost delta-v transfer to patient players.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `search_duration` | Maximum of origin orbital period, destination orbital period or their synodic period | Duration in seconds as `Scalar` |

### Maximum time of flight

Maximum duration of the transfer orbit between origin and destination. Some reasons this may come in useful:
* Life support mod installed
* Challenge requirement
* Career mode contract deadline

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `max_time_of_flight` | Twice the time of a idealized Hohmann transfer between origin and destination | Duration in seconds as `Scalar` |

### Initial Orbit Altitude

The initial orbit should be as close as possible to a circular orbit with 0° inclination to ensure maximum accuracy. The desired altitude can be specified exactly in meters. For fans of the [Oberth effect](https://en.wikipedia.org/wiki/Oberth_effect) the special value "min" sets the altitude to either 10km above the surface for airless bodies or 10km above the atmosphere.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `initial_orbit_altitude` | 100,000m | Altitude in meters as `Scalar` or the special `String` value "min" |

### Final Orbit Type

The insertion orbit can be one of three types:
* **None**
    Use when an aerocapture, flyby or extreme lithobraking is intended at the destination. When calculating the total delta-v the insertion portion is considered zero.
* **Circular**
    Capture into a circular orbit at the altitude specified by `final_orbit_pe`. Does not change inclination. If the origin and destination bodies are inclined then this orbit will be inclined too.
* **Elliptical**
    Capture into a highly elliptical orbit with apoapsis *just* inside the destination's SOI and periapsis at the altitude specified by `final_orbit_pe`. This can come in useful if the vessel will send a separate lander down to the surface or it's intended to visit moons of the destination.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `final_orbit_type` | Circular | One of `String` values "none", "circular" or "elliptical"  |

### Final Orbit Periapsis

Sets destination orbit desired periapsis in meters. Those who like to live dangerously can use the special value "min" to set the altitude to either 10km above the surface for airless bodies or 10km above the atmosphere. Note: This may not be high enough to clear surface features! Use at your own peril.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `final_orbit_pe` | 100,000m | Altitude in meters as `Scalar` or the special `String` value "min" |

## Differences between Bodies and Vessels

Celestial bodies and vessels are treated slightly differently. Setting a vessel as the origin disables the `initial_orbit_altitude` option. In a similar fashion, setting a vessel as the destination disables the `final_orbit_type` and `final_orbit_pe` options.

## Technical Details

### Lambert Solver [(lambert.ks)](https://github.com/maneatingape/rsvp/blob/master/lambert.ks)

The core functionality is built around a [Lambert's problem](https://en.wikipedia.org/wiki/Lambert%27s_problem) solver. Given the position of two planets and a duration, this calculates the delta-v required for a transfer orbit between the two positions that will take exactly that duration.

The Lambert solver code is a kOS port of the [PyKep project](https://github.com/esa/pykep) developed by the European Space Agency. The algorithm and equations are described in excellent detail in the paper [Revisiting Lambert’s problem](https://www.esa.int/gsp/ACT/doc/MAD/pub/ACT-RPR-MAD-2014-RevisitingLambertProblem.pdf) by Dario Izzio.

The original code is very robust and flexible. For the KSP universe some simplifications have been made, in particular multi-revolution transfer orbits are not considered. Interestingly, the Kerboscript code is more concise than the C++ original, thanks to first class support for vector math and the exponent operator, coming in at around 100 lines not including comments.


### Coordinate Descent [(search.ks)](https://github.com/maneatingape/rsvp/blob/master/search.ks)

Graphing the delta-v values returned by the Lambert solver, with departure time along the x-axis and arrival time (or time of flight) along the y-axis, yields the famous [porkchop plot.](https://en.wikipedia.org/wiki/Porkchop_plot) This shows the lowest delta-v transfer times between two planets.

However the brute force approach of generating every point of this graph would take far too long on kOS. Instead an [iterated local search](https://en.wikipedia.org/wiki/Iterated_local_search) gives a decent probability of finding the global minimum in a shorter time.

The [coordinate descent](https://en.wikipedia.org/wiki/Coordinate_descent) implementation used is a variant of the classic [hill climbing](https://en.wikipedia.org/wiki/Hill_climbing) algorithm. Given a starting point, it always attempts to go "downhill" to a region of lower delta-v, stopping once it cannot go any further.λ

### Orbital Utilities [(orbit.ks)](https://github.com/maneatingape/rsvp/blob/master/orbit.ks)

Collection of functions that:
* Use the [vis-viva equation](https://en.wikipedia.org/wiki/Vis-viva_equation) to calculate the delta-v between elliptical orbits and hyperbolic transfers, in order to determine the ejection and insertion delta-v values.
* Provide default value for the time of flight based on the [Hohmann transfer](https://en.wikipedia.org/wiki/Hohmann_transfer_orbit) period.
* Provide default value for search duration based on [Synodic period](https://en.wikipedia.org/wiki/Orbital_period#Synodic_period).

## Future Features

Planned additions to the library. Items in this list may be added, removed or changed at any time.

* **[WIP] Manuever node creator**
    Create manuever nodes to implement the desired transfer, based on the data returned from the `find_launch_window` function. Currently a very rough version that creates a node for vessel-to-vessel transfers lives in `main.ks`.
* **Impatience factor**
    Apply a weighting factor based on departure time when comparing transfers. This is so that transfers that are higher delta-v but occur sooner are still considered in order to reduce time-warping. For example a transfer in 1 year that is 10 m/s higher than a transfer in 3 years may be more convenient.