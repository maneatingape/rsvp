# RSVP [![Release Version](https://img.shields.io/github/v/release/maneatingape/rsvp)](https://github.com/maneatingape/rsvp/releases/latest) [![Release Downloads](https://img.shields.io/github/downloads/maneatingape/rsvp/total)](https://github.com/maneatingape/rsvp/releases/latest)

*RSVP* is a [kOS](https://ksp-kos.github.io/KOS/) library that finds orbital [launch windows](https://en.wikipedia.org/wiki/Launch_window) in the game [Kerbal Space Program](https://www.kerbalspaceprogram.com/).
The acronym stands for "Rendezvous s’il vous plaît", a playful pun on the regular meaning of the phrase.

This library enables players to make automated low delta-v transfers between two planets or vessels in-game, either directly from their own kOS scripts or from the kOS console. It provides a scriptable alternative to existing tools, such as the excellent web based [Launch Window Planner](https://alexmoon.github.io/ksp/) or the snazzy [MechJeb Maneuver Planner](https://github.com/MuMech/MechJeb2/wiki/Maneuver-Planner).

## Features

* Integrates with your kOS scripts.
* Creates departure and arrival maneuver nodes.
* Supports rendezvous between vessels, planets, moons, asteroids and comets.
* Adapts to planetary packs such as [Galileo's Planet Pack](https://forum.kerbalspaceprogram.com/index.php?/topic/152136-ksp-181-galileos-planet-pack-v164-01-july-2020/), [Outer Planets Mods](https://forum.kerbalspaceprogram.com/index.php?/topic/184789-131-18x-outer-planets-mod-v226-4th-feb-2020/) and [JNSQ](https://forum.kerbalspaceprogram.com/index.php?/topic/184880-181-jnsq-090-03-feb-2020/).

This short video shows these features in action:
[![Demo Video](doc/images/demo_preview.png)](https://vimeo.com/442344803)

## Quickstart

1. Go to the [Releases](https://github.com/maneatingape/rsvp/releases) tab, then download latest version of `rsvp.zip`.
2. Unzip into `<KSP install location>/Ships/Script` directory. This step adds the library to the kOS archive volume, making it available to all vessels.
3. Launch a craft into a stable orbit of Kerbin.
4. Run this script from the craft:
    ```
    set config:ipu to 2000.
    runoncepath("0:/rsvp/main").
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

### Cleanup Maneuver Nodes

If any problems are enountered when creating the transfer then remove and cleanup any maneuver nodes that have been created. Defaults to true but can be disabled for debugging purposes.

| Key | Default value | Accepted values |
|:----|:--------------|:----------------|
| `cleanup_maneuver_nodes` | True | `Boolean` |

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
    Capture into a highly elliptical orbit with apoapsis *just* inside the destination's SOI and periapsis at the altitude specified by `final_orbit_periapsis`. This can come in useful if the vessel will send a separate lander down to the surface or the intention is to visit moons of the destination.

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

RSVP is designed with some quality of life features to make it as straightforward as possible to use within your own scripts.

* There is only a single global `rsvp` variable as the entrypoint. All other functions, variables and delegates are locally scoped so that you don't have to worry about name collisions.
* The library can be located anywhere as long as all script files are in the same directory. The suggested location is `0:/rsvp`, however you are free to choose any other volume or path.
* Detailed return values indicate success or failure. The return value is a lexicon that will always have a top-level boolean `success` key. Check this value before proceeding with the rest of your script.

    For example, a successful result is:
    ```
    LEXICON of 3 items:
    ["success"] = True
    ["predicted"] = LEXICON of 2 items:
      ["departure"] = LEXICON of 2 items:
        ["time"] = 5055453.38357352
        ["deltav"] = 1036.59841185951
      ["arrival"] = LEXICON of 2 items:
        ["time"] = 10766955.6939971
        ["deltav"] = 642.186439333725
    ["actual"] = LEXICON of 2 items:
      ["departure"] = LEXICON of 2 items:
        ["time"] = 5055629.63357352
        ["deltav"] = 1056.03106245216
      ["arrival"] = LEXICON of 2 items:
        ["time"] = 10768356.5846979
        ["deltav"] = 647.973826829273
    ```
    An example of a transfer with problems is:
    ```
    LEXICON of 2 items:
    ["success"] = False
    ["problems"] = LEXICON of 2 items:
      [1] = "Option 'verbose' is 'qux', expected boolean"
      [303] = "Option 'foo_bar' not recognised"
    ```
* To save space on the limited hard disks of kOS processors you can compile the source to `.ksm` files that are about 20% of the size of the raw source. A convenience `rsvp:compile_to` function exists for this purpose. For example, the following code will compile the source from the archive then copy the compiled files to the hard disk of the current processor.
    ```
    runoncepath("0:/rsvp/main").
    createdir("1:/rsvp").
    rsvp:compile_to("1:/rsvp").
    ```

## Technical Details

The [source code readme](src) contains detailed descriptions of the under-the-hood mechanisms. Each script file is thoroughly commented to describe both what the code is doing, but also more importantly *why*.

## Suggest a feature or report a bug

If you have an idea for a feature or have found a bug then you can [create an issue here](https://github.com/maneatingape/rsvp/issues/new/choose). Before you do so, please check that the issue doesn't already exist in the [isses list](https://github.com/maneatingape/rsvp/issues).