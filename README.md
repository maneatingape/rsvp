# RSVP

*RSVP* is a [kOS](https://ksp-kos.github.io/KOS/) library that finds orbital [launch windows](https://en.wikipedia.org/wiki/Launch_window) in the game [Kerbal Space Program](https://www.kerbalspaceprogram.com/).
The acronym stands for "Rendezvous s’il vous plaît", a playful pun on the regular meaning of the phrase.

This library enables players to make automated low delta-v transfers between two planets or vessels in-game, either directly from their own kOS scripts or from the kOS console. It provides a scriptable alternative to existing tools, such as the excellent web based [Launch Window Planner](https://alexmoon.github.io/ksp/) or the snazzy [MechJeb Maneuver Planner](https://github.com/MuMech/MechJeb2/wiki/Maneuver-Planner).

[![](https://github.com/maneatingape/rsvp/workflows/Latest%20Release/badge.svg)](https://github.com/maneatingape/rsvp/releases/latest)
[![](https://img.shields.io/github/v/release/maneatingape/rsvp)](https://github.com/maneatingape/rsvp/releases/latest)
[![](https://img.shields.io/github/downloads/maneatingape/rsvp/total)](https://github.com/maneatingape/rsvp/releases/latest)

## Features

* Integrates with your kOS scripts.
* Creates departure and arrival maneuver nodes.
* Supports rendezvous between vessels, planets, moons, asteroids and comets.

## Quickstart

1. Go to the [Releases](https://github.com/maneatingape/rsvp/releases) tab, then download latest version of `rsvp.zip`.
2. Unzip into `<KSP install location>/Ships/Script` directory. This step adds the library to the kOS archive volume, making it available to all vessels.
3. Launch a craft into a stable orbit of Kerbin.
3. Run this script from the craft:
    ```
    runoncepath("0:/rsvp/main.ks").

    // Default value is 250. Overclocking CPU speed to maximum is recommended
    // as finding transfers is computationally intensive.
    set config:ipu to 2000.

    local options is lexicon("create_maneuver_nodes", "both", "verbose", true).
    rsvp:goto(duna, options).
    ```
This will find the next transfer window from Kerbin to Duna then create the corresponding maneuver nodes necessary to make the journey. Additionally it will print details to the console during the search.

---

## Configuration

The following options allow players to customize and tweak the desired transfer orbit. The general philosophy is that sensible defaults are provided for each option so that only custom values need to be provided. Specify options by adding them as key/value pairs to the `options` lexicon parameter.

### Verbose

Prints comprehensive details to the kOS console if set to "True".

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `verbose` | False | `Boolean` |

### Create Maneuver Nodes

Whether or not to create maneuver nodes that will execute the desired journey. The value "none" can be used for planning, the script will return details of the next transfer window.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `create_maneuver_nodes` | None | One of `String` values "none", "first" or "both" |

### Earliest Departure

When to start searching for transfer windows. Time can be in the vessel's past, present or future. The only restriction is that the time must be greater than the epoch time (Year 1, Day 1, 0:00:00)

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `earliest_departure` | Current universal time of CPU vessel plus 2 minutes | Seconds from epoch as `Scalar` |

### Search Duration

Only search for transfer windows within the specified duration from earliest departure. Restricting the search duration can come in handy when time is of the essence. Increasing the duration may reveal a lower cost delta-v transfer to patient players.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `search_duration` | Maximum of origin orbital period, destination orbital period or their synodic period | Duration in seconds as `Scalar` |

### Search Interval

How frequently new sub-searches are started within the search duration. Lower values may result in better delta-v values being discovered, however the search will take longer to complete.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `search_interval` | Half the minimum of origin orbital period and destination orbital period | Duration in seconds as `Scalar` |

### Maximum time of flight

Maximum duration of the transfer orbit between origin and destination. Some reasons it may come in useful to adjust this are life support mods, challenge requirements and career mode contract deadlines.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `max_time_of_flight` | Twice the time of a idealized Hohmann transfer between origin and destination | Duration in seconds as `Scalar` |

### Final Orbit Periapsis[*](#note-on-vessel-rendezvous)

Sets desired destination orbit periapsis in meters.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `final_orbit_periapsis` | 100,000m | Altitude in meters as `Scalar` |

### Final Orbit Type[*](#note-on-vessel-rendezvous)

The insertion orbit can be one of three types:
* **None**
    Use when an aerocapture, flyby or extreme lithobraking is intended at the destination. When calculating the total delta-v the insertion portion is considered zero.
* **Circular**
    Capture into a circular orbit at the altitude specified by `final_orbit_periapsis`. Does not change inclination. If the origin and destination bodies are inclined then this orbit will be inclined too.
* **Elliptical**
    Capture into a highly elliptical orbit with apoapsis *just* inside the destination's SOI and periapsis at the altitude specified by `final_orbit_periapsis`. This can come in useful if the vessel will send a separate lander down to the surface or its intended to visit moons of the destination.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `final_orbit_type` | Circular | One of `String` values "none", "circular" or "elliptical" |

### Final Orbit Orientation[*](#note-on-vessel-rendezvous)

The orbit orientation can be one of three types:
* **Prograde**
    Rotation of the final orbit will be the same as the rotation of the planet. Suitable for most missions.
* **Polar**
    Orbit will pass over the poles of the planet at 90 degrees inclination. Useful for survey missions.
* **Retrograde**
    Orbit will be the opposite to the rotation of the planet. An example use for this setting is solar powered craft that need to arrive on the daylight side of the planet.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `final_orbit_orientation` | Prograde | One of `String` values "prograde", "polar" or "retrograde" |

### Note on Vessel rendezvous

Vessel destinations are treated slightly differently to Celestial body destinations. Setting a vessel as the destination disables the `final_orbit_periapsis`, `final_orbit_type` and `final_orbit_orientation` options.

--- 

## Integrating with your scripts

TODO

## Technical Details

The [source code readme](src) contains detailed descriptions of the under-the-hood mechanisms. Each script file is thoroughly commented to describe both what the code is doing, but also more importantly *why*.

## Known Issues

The library endeavours to be as flexible as possible, however there are some situations that it currently can't handle:

* **Transfers *from* moons are not working**
    Transfers *to* moons work just fine, however transfers that eject from a moon to either another moon or a vessel in orbit of the parent planet are going astray. Smaller moons such as Gilly, Minmus, Bop and Pol seem less affected.  
    As a workaround, eject from the moon first in approximately the right direction, then plot a follow-up vessel-to-vessel or vessel-to-body transfer.
* **Polar orbit of Mun from LKO and polar orbit of Ike from LDO produce very high delta transfers**
    These moons are very close to their parent planet relative to the size of their SOI, so the assumption that the transfer logic makes when calculating orbtial offset is not efficient.
    As a workaround, specify an elliptical prograde final orbit then change inclination at apoapsis.


## Suggest a feature or report a bug

If you have an idea for a feature or have found a bug then you can [create an issue here](https://github.com/maneatingape/rsvp/issues/new/choose). Before you do so, please check that the issue doesn't already exist, either in the isses list or the [Project Board](https://github.com/maneatingape/rsvp/projects/1).