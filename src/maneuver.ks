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
        "encounter_details", helper@:bind(maneuver, from_vessel, encounter_details@),
        "periapsis_time", helper@:bind(maneuver, from_vessel, periapsis_time@),
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

// Finds the first orbital patch that matches destination, then calls the
// specified implementation function.
local function helper {
    parameter maneuver, from_vessel, implementation, destination.

    local orbit is maneuver:orbit.
    local adjustment_needed is from_vessel and destination:hasbody and destination:body:hasbody.

    until not orbit:hasnextpatch {
        local arrival_time is time():seconds + orbit:nextpatcheta.
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            return implementation(destination, arrival_time, adjustment_needed).
        }
    }

    return "none".
}

// Returns the predicted time, velocity and periapsis of the ship at the
// exact moment when it will enter the destination's SOI.
local function encounter_details {
    parameter destination, arrival_time, adjustment_needed.

    local arrival_velocity is velocityat(ship, arrival_time):orbit.
    local arrival_periapsis is orbitat(ship, arrival_time):periapsis.

    // When the destination is a moon (rather than a planet) then
    // "velocityat" returns value relative to the parent planet *not*
    // the moon, even though ship is within moon's SOI at "arrival_time".
    if adjustment_needed {
        local adjustment is velocityat(destination, arrival_time):orbit.
        set arrival_velocity to arrival_velocity - adjustment.
    }

    return lex(
        "time", arrival_time,
        "velocity", arrival_velocity,
        "periapsis", arrival_periapsis
    ).
}

// Find the periapsis time by using line search to find the closest point
// between the ship and destination.
local function periapsis_time {
    parameter destination, arrival_time, adjustment_needed.

    // The "positionat" function behaves differently when predicting the future
    // position of the ship relative to planets and moons.
    function planet_cost {
        parameter v.
        return (positionat(ship, v:x) - destination:position):mag.
    }

    function moon_cost {
        parameter v.
        return (positionat(ship, v:x) - positionat(destination, v:x)):mag.
    }

    local cost is choose moon_cost@ if adjustment_needed else planet_cost@.
    local result is rsvp:line_search(cost@, arrival_time, 21600, 1).

    return result:position:x.
}

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