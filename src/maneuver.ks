@lazyglobal off.

parameter export.
export("create_maneuver", create_maneuver@).

// Convenience wrapper around a maneuver node
local function create_maneuver {
    parameter destination, epoch_time, deltav.

    local maneuver is node(epoch_time, deltav:x, deltav:y, deltav:z).
    add maneuver.

    return lexicon(
        "delete", delete@:bind(maneuver),
        "departure_time", departure_time@:bind(maneuver),
        "patch_time", patch_time@:bind(maneuver),
        "deltav", get_deltav@:bind(maneuver),
        "distance_to_periapsis", distance_to_periapsis@:bind(destination, maneuver),
        "time_to_periapsis", time_to_periapsis@:bind(destination, maneuver),
        "speed_at_soi", speed_at_soi@:bind(destination, maneuver),
        "time_at_soi", time_at_soi@:bind(destination, maneuver)
    ).
}

local function delete {
    parameter maneuver.

    remove maneuver.
}

local function departure_time {
    parameter maneuver.

    return time():seconds + maneuver:eta.
}

local function patch_time {
    parameter maneuver.    

    return time():seconds + maneuver:orbit:nextpatcheta.
}

local function get_deltav {
    parameter maneuver.    

    return maneuver:deltav:mag.
}

// TODO: There may be a accidental moon intercept.
local function distance_to_periapsis {
    parameter destination, maneuver, final_orbit_periapsis.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            local altitude is orbit:body:radius + orbit:final_orbit_periapsis.
            local desired is orbit:body:radius + final_orbit_pe.

            return abs(altitude - desired).
        }
    }

    return "max".
}

// TODO: There may be a accidental moon intercept.
local function time_to_periapsis {
    parameter destination, maneuver.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        local start is orbit:nextpatcheta.
        set orbit to orbit:nextpatch.
        local end is orbit:nextpatcheta.

        if orbit:body = destination {
            return time():seconds + (start + end) / 2.
        }
    }

    return "max".
}

// TODO: There may be a accidental moon intercept.
local function speed_at_soi {
    parameter destination, maneuver.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        local start is orbit:nextpatcheta.
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            return velocityat(ship, time():seconds + start):orbit.
        }
    }

    return "max".
}

// TODO: There may be a accidental moon intercept.
local function time_at_soi {
    parameter destination, maneuver.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        local start is orbit:nextpatcheta.
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            return time():seconds + start.
        }
    }

    return "max".
}