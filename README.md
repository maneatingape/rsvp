# Description

*RSVP* is a [kOS](https://ksp-kos.github.io/KOS/) library that finds orbital [launch windows](https://en.wikipedia.org/wiki/Launch_window) in the game [Kerbal Space Program](https://www.kerbalspaceprogram.com/). The initials stand for "Rendezvous s’il vous plaît", a playful twist on the normal meaning on the acronym.

This library enables players to make automated low delta-v transfer orbits between two planets or vessels in-game, either directly from their own kOS scripts or from the kOS console. It provides a scriptable alternative to existing tools, such as the excellent web based [Launch Window Planner](https://alexmoon.github.io/ksp/) or the snazzy [MechJeb Maneuver Planner](https://github.com/MuMech/MechJeb2/wiki/Maneuver-Planner).

## Features

* Integrates with your kOS scripts, supporting interplanetary travel.
* Adapts to planetary packs such as [Outer Planets Mods](https://forum.kerbalspaceprogram.com/index.php?/topic/184789-131-18x-outer-planets-mod-v226-4th-feb-2020/), [RSS](https://github.com/KSP-RO/RealSolarSystem) and [JNSQ](https://github.com/Galileo88/JNSQ).
* Supports vessel to vessel rendezvous e.g. docking, rescue missions

## Quickstart

1. Go to the "Releases" tab then download the latest version as a zip or tar file.
2. Unpack this file into the `<KSP install location>/Ships/Script` location creating a directory `rsvp`. This adds the scripts to the kOS archive volume, making them available to all vessels.
3. Call the entry point from your own script:
    ```
    runoncepath("0:rsvp/main.ks").

    // Default value is 250. Increasing CPU speed to maximum is recommended
    // as finding transfers is computationally intensive.
    set config:ipu to 2000.

    local options is lexicon("verbose", true).
    find_launch_window(kerbin, duna, options).
    ```
This will print the time of the next transfer window from Kerbin to Duna to the console using the following defaults:
* Earliest departure time is the current universal time of the vessel.
* Departure orbit is circular at 100km altitude with 0° inclination.
* Arrival orbit is circular at 100km altitude.

## Configuration

The following options allow players to customize and tweak the desired transfer orbit. The general philosophy is that sensible defaults are provided for each option so that only custom values need to be provided. Add desired options as key/value pairs to the `options` lexicon parameter.

### Earliest Departure

When to start searching for transfer windows. Time can be in the vessel's past, present or future. The only restriction is that the time must be greater than or equal to the epoch time (Year 1, Day 1, 0:00:00)

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `earliest_departure` | Current universal time of CPU vessel | Seconds from epoch as `Scalar` or `Timespan` |

### Search Duration

Only search for transfer windows in the specified duration from earliest departure. Restricting the search duration can come in handy if time is of the essence. Increasing the duration may reveal even lower cost delta-v transfer for very patient players.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `search_duration` | Maximum of origin orbital period, destination orbital period or their synodic period | Duration in seconds as `Scalar` |

### Maximum time of flight

Maximum duration of the transfer orbit between origin and destination. Some reasons this may come in useful:
* Life support mod installed
* Meet forum challenge requirement
* Career mode contract deadline

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `max_time_of_flight` | Twice the time of a idealized Hohmann transfer between origin and destination | Duration in seconds as `Scalar` |

### Initial Orbit Altitude

The initial orbit should be as close as possible to a circular orbit with 0° inclination to ensure maximum accuracy. The desired altitude can be specified exactly in meters. For fans of the [Oberth effect](https://en.wikipedia.org/wiki/Oberth_effect) the special value "min" sets the altitude to 10km above the surface for airless bodies or 10km above the atmosphere.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `initial_orbit_altitude` | 100,000m | Altitude in meters as `Scalar` or the special `String` value "min" |

### Final Orbit Type

The insertion orbit can be one of three types:
* **None**
    Use when an aerocapture or flyby is intended at the destination. When calculating the total delta-v the insertion delta-v portion is considered zero.
* **Circular**
    Propulsively brake into a circular orbit at the altitude specified by the next option. Does not change inclination. If the origin and destination bodies are inclined then this orbit will be inclined too.
* **Elliptical**
    Capture into a highly elliptical orbit with apoapsis *just* inside the destination's SOI and periapsis at the desired altitude specified by the next option. This can useful if, for example the vessel will send a separate lander down to the surface or it is intended to visit moons of the destination.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `final_orbit_type` | Circular | One of `String` values "none", "circular" or "elliptical"  |

### Final Orbit Periapsis

Sets destination orbit desired altitude or periapsis in meters. For folks who like to live dangerously the special value "min" sets the altitude to 10km above the surface for airless bodies or 10km above the atmosphere. Note: This may not be high enough to clear surface features! Use at your own peril.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `final_orbit_pe` | 100,000m | Altitude in meters as `Scalar` or the special `String` value "min" |

### Verbose

Prints search details to the kOS console if set to true.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `verbose` | False | `Boolean` |

## Vessel to vessel

[TODO]

## Technical Details

### Lambert Solver [(lambert.ks)](https://github.com/maneatingape/kos-launch-window-finder/blob/master/lambert.ks)

The core functionality is built around a [Lambert's problem](https://en.wikipedia.org/wiki/Lambert%27s_problem) solver. Given the position of two planets and a duration, this calculates the delta-v required for a transfer orbit between the two positions that will take exactly that duration.

The Lambert solver code is a kOS port of the [PyKep project](https://github.com/esa/pykep) developed by the European Space Agency. The algorithm and equations are described in excellent detail in the paper [Revisiting Lambert’s problem](https://www.esa.int/gsp/ACT/doc/MAD/pub/ACT-RPR-MAD-2014-RevisitingLambertProblem.pdf) by Dario Izzio.

The original code is very robust and flexible. For the KSP universe some simplifications have been made, in particular multi-revolution transfer orbits are not considered.


### Coordinate Descent [(search.ks)](https://github.com/maneatingape/kos-launch-window-finder/blob/master/search.ks)

Graphing the delta-v values returned by the Lambert solver, with departure time along the x-axis and arrival time (or time of flight) along the y-axis, gives the famous [porkchop plot.](https://en.wikipedia.org/wiki/Porkchop_plot) This shows the lowest delta-v transfer times between two planets.

However the brute force approach of generating every point of this graph would take far too long on kOS. Instead an [iterated local search](https://en.wikipedia.org/wiki/Iterated_local_search) gives a decent probability of finding the global minimum in a shorter time.

The [coordinate descent](https://en.wikipedia.org/wiki/Coordinate_descent) algorithm used is a variant of the classic [hill climbing](https://en.wikipedia.org/wiki/Hill_climbing) algorithm. Given a starting point, it always attempts to go "downhill" to a region of lower delta-v, stopping once it cannot go any further. 

### Orbital mechanics [(orbit.ks)](https://github.com/maneatingape/kos-launch-window-finder/blob/master/orbit.ks)

[TODO]

## Future Features

Planned additions to the library. Items in this may be added, removed or changed at any time.

* **[WIP] Manuever node creator**
    Create manuever nodes to implement the desired transfer, based on the data returned from the `find_launch_window` function. Currently a very early version that creates a node for vessel-to-vessel transfers lives in `main.ks` 
* **Impatience factor**
    Apply a weighting factor based on departure time when comparing transfers. This is so that transfers that are higher delta-v but occur sooner are still considered in order to reduce time-warping. For example a transfer in 1 year that is 10 m/s higher than a transfer in 3 years may be more convenient.