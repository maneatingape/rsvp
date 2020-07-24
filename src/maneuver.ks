@lazyglobal off.

parameter export.
export("create_maneuver", create_maneuver@).

// Convenience wrapper around a maneuver node that provides methods to predict
// details of future encounters.
local function create_maneuver {
    parameter from_vessel, epoch_time, deltav.

    local maneuver is node(epoch_time, deltav:x, deltav:y, deltav:z).
    add maneuver.

    return lex(
        "time", node_time@:bind(maneuver),
        "deltav", node_deltav@:bind(maneuver),
        "delete", node_delete@:bind(maneuver),
        "patch_details", patch_details@:bind(maneuver, from_vessel),
        "validate_patches", validate_patches@:bind(maneuver)
    ).
}

local function node_time {
    parameter maneuver.

    return time():seconds + maneuver:eta.
}

local function node_deltav {
    parameter maneuver.

    return maneuver:deltav:mag.
}

local function node_delete {
    parameter maneuver.

    remove maneuver.
}

// Finds the first orbital patch that matches destination body, then returns
// the predicted time, velocity and periapsis details of the ship at the exact
// moment when it will enter the destination's SOI.
local function patch_details {
    parameter maneuver, from_vessel, destination.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        local soi_time is time():seconds + orbit:nextpatcheta.
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            local soi_velocity is velocityat(ship, soi_time):orbit.
            local periapsis_altitude is orbit:periapsis.
            local periapsis_time is rsvp:time_at_periapsis(orbit).

            // When the destination is a moon (rather than a planet) then
            // "velocityat" returns value relative to the parent planet *not*
            // the moon, even though ship is within moon's SOI at "patch_time".
            if from_vessel and destination:hasbody and destination:body:hasbody {
                local adjustment is velocityat(destination, soi_time):orbit.
                set soi_velocity to soi_velocity - adjustment.
            }

            return lex(
                "soi_time", soi_time,
                "soi_velocity", soi_velocity,
                "periapsis_altitude", periapsis_altitude,
                "periapsis_time", periapsis_time
            ).
        }
    }

    return "none".
}

// Validate that the actual projected orbit patches match expectation.
// This checks for any unexpected encounters along the way,
// for example Kerbin's Mun or Duna's Ike getting in the way.
local function validate_patches {
    parameter maneuver, expected, arrival_time.

    local orbit is maneuver:orbit.
    local actual is list().

    actual:add(orbit:body).

    until not orbit:hasnextpatch or arrival_time < time():seconds + orbit:nextpatcheta {
        set orbit to orbit:nextpatch.
        actual:add(orbit:body).
    }

    if list_equals(expected, actual) {
        return lex("success", true).
    }
    else {
        local message is "Unexpected encounter " + to_string(actual) + ", expected " + to_string(expected).
        return lex("success", false, "problems", lex(401, message)).
    }
}

// Compare two lists for equality
local function list_equals {
    parameter first, second.

    if first:length <> second:length {
        return false.
    }

    for i in range(0, first:length) {
        if first[i] <> second[i] {
            return false.
        }
    }

    return true.
}

local function to_string {
    parameter items.

    local names is list().

    for item in items {
        names:add(item:name).
    }

    return "'" + names:join(" => ") + "'".
}