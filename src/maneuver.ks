@lazyglobal off.

parameter export.
export("create_maneuver", create_maneuver@).

// Convenience wrapper around a maneuver node
local function create_maneuver {
    parameter destination, epoch_time, deltav.

    local maneuver is node(epoch_time, deltav:x, deltav:y, deltav:z).
    add maneuver.

    return lex(
        "delete", delete@:bind(maneuver),
        "departure_time", departure_time@:bind(maneuver),
        "deltav", get_deltav@:bind(maneuver),
        "patch_time", patch_time@:bind(maneuver),
        "osv_at_destination_soi", osv_at_destination_soi@:bind(destination, maneuver),
        "distance_to_periapsis", distance_to_periapsis@:bind(destination, maneuver),
        "details_at_periapsis", details_at_periapsis@:bind(destination, maneuver)
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

local function get_deltav {
    parameter maneuver.

    return maneuver:deltav:mag.
}

// TODO: There may be a accidental moon intercept.
local function patch_time {
    parameter maneuver.

    return time():seconds + maneuver:orbit:nextpatcheta.
}

// Returns the predicted time and velocity of the ship at the exact moment
// when it will enter the destination's SOI.
local function osv_at_destination_soi {
    parameter destination, maneuver.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        local arrival_time is time():seconds + orbit:nextpatcheta.
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            local arrival_velocity is velocityat(ship, arrival_time):orbit.

            // When the destination is a moon (rather than a planet) then
            // "velocityat" returns value relative to the parent planet *not*
            // the moon, even though ship is within moon's SOI at 'arrival_time'.
            if destination:body:hasbody {
                local adjustment is velocityat(destination, arrival_time):orbit.
                set arrival_velocity to arrival_velocity - adjustment.
            }

            return lex(
                "success", true,
                "time", arrival_time,
                "velocity", arrival_velocity
            ).
        }
    }

    return lex("success", false).
}

local function distance_to_periapsis {
    parameter destination, maneuver, final_orbit_periapsis.
// Returns the altitude at destination periapsis. Searches all orbit patches
// in case user has increased CONIC_PATCH_LIMIT and there is an accidental moon
// intercept. For example if destination is Duna but Ike gets in the way, then
// there will be *two* orbit patches for Duna, each with different periapsis.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            return abs(orbit:periapsis - final_orbit_periapsis).
        }
    }

    return "max".
}

local function details_at_periapsis {
    parameter destination, maneuver.

    local orbit is maneuver:orbit.
    local periapsis_details is "max".

    // The "positionat" function behaves differently between planets and moons
    // when predicting their future position relative to the ship.
    function planet_cost {
        parameter v.
        return (positionat(ship, v:x) - destination:position):mag.
    }

    function moon_cost {
        parameter v.
        return (positionat(ship, v:x) - positionat(destination, v:x)):mag.
    }

    local cost is choose moon_cost@ if destination:body:hasbody else planet_cost@.

    until not orbit:hasnextpatch {
        local start_time is time():seconds + orbit:nextpatcheta.
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            local result is rsvp:line_search(cost@, start_time, 21600, 1).
            set periapsis_details to lex(
                "time", result:position:x,
                "altitude", result:minimum - destination:radius
            ).
        }
    }

    return periapsis_details.
}