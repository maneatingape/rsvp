@lazyglobal off.

parameter base_path is "0:/rsvp".

global rsvp is lexicon().

import("orbit.ks").
import("search.ks").
import("validate.ks").
import("lambert.ks").

export("find_launch_window", find_launch_window@).

local function import {
    parameter filename.

    runoncepath(base_path + "/" + filename, export@).
}

local function export {
    parameter key, value.

    rsvp:add(key, value).
}

local function find_launch_window {
    parameter destination, options is lexicon().

    local result is rsvp:validate_parameters(destination, options).
    if not result:success return result.

    local settings is result:settings.
    local origin is settings:origin.
    local transfer_details is rsvp:transfer_deltav:bind(origin, destination).
    local ejection_deltav is rsvp[settings:initial_orbit_type]:bind(origin, settings:initial_orbit_pe).
    local insertion_deltav is rsvp[settings:final_orbit_type]:bind(destination, settings:final_orbit_pe).

    function total_deltav {
        parameter flip_direction, departure_time, time_of_flight.

        local details is transfer_details(flip_direction, departure_time, departure_time + time_of_flight).
        return ejection_deltav(details) + insertion_deltav(details).
    }

    local transfer is rsvp:iterated_local_search(settings, total_deltav@).

    local result is lexicon().
    result:add("success", true).
    result:add("estimated_departure_time", transfer:departure_time).
    result:add("estimated_arrival_time", transfer:arrival_time).
    result:add("estimated_total_deltav", transfer:total_deltav).

    // First check point. If no nodes are requests then we're done.
    if settings:create_maneuver_nodes = "none" return result.

    local maneuver is from_origin(origin, destination, transfer, v(0, 0, 0)).

    // If the destination is a vessel (including asteroids or comets) then our
    // intercept is already accurate enough and maneuver refinement has no benefit.
    //
    // For planets, our intercept is usually *too* accurate that it hits the planet
    // dead center, which is not usually what you want. So we tweak the intercept
    // in order to approximate the desired periapsis in a prograde direction.
    if destination:typename = "body" {
        local arrival_time is time_at_soi(destination, maneuver).
        local arrival_velocity is speed_at_soi(destination, maneuver).
        local offset is rsvp:impact_parameter_offset(destination, arrival_time, arrival_velocity, settings:final_orbit_pe, "prograde").

        remove maneuver.
        set maneuver to from_origin(origin, destination, transfer, offset).
    }

    result:add("actual_departure_time", time:seconds + maneuver:eta).
    result:add("actual_ejection_deltav", maneuver:deltav:mag).

    return result.
}

local function from_origin {
    parameter origin, destination, transfer, offset.

    local flip_direction is transfer:flip_direction.
    local departure_time is transfer:departure_time.
    local arrival_time is transfer:arrival_time.

    if origin:typename = "body" {
        return from_body(origin, destination, flip_direction, departure_time, arrival_time, offset).
    }
    else {
        return from_vessel(origin, destination, flip_direction, departure_time, arrival_time, offset).
    }
}

local function from_vessel {
    parameter origin, destination, flip_direction, departure_time, arrival_time, offset.

    local details is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time, ship:body, offset).
    local osv is rsvp:orbital_state_vectors(ship, departure_time).
    local projection is rsvp:maneuver_node_vector_projection(osv, details:dv1).

    return create_then_add_node(departure_time, projection).
}

local function from_body {
    parameter origin, destination, flip_direction, departure_time, arrival_time, offset.

    local delta is v(1, 0, 0).
    local iterations is 0.

    local details is rsvp:transfer_deltav(origin, destination, flip_direction, departure_time, arrival_time, origin:body, offset).
    local departure_deltav is details:dv1.
    local maneuver is create_maneuver_node_in_correct_location(origin, departure_time, departure_deltav).

    until delta:mag < 0.001 or iterations = 15 {
        local t2 is time():seconds + maneuver:orbit:nextpatcheta.
        local details is rsvp:transfer_deltav(ship, destination, flip_direction, t2, arrival_time, ship:body:body, offset).

        set delta to details:dv1.
        set iterations to iterations + 1.
        set departure_time to time:seconds + maneuver:eta.
        set departure_deltav to departure_deltav + delta.

        remove maneuver.
        set maneuver to create_maneuver_node_in_correct_location(origin, departure_time, departure_deltav).
    }

    return maneuver.
}

// Creates maneuver node at the correct location around the origin planet in
// order to eject at the desired orientation.
// Using the raw magnitude of the delta-v as our cost function handles
// mutliple situtations and edge cases in one simple robust approach.
// For example prograde/retrograde ejection combined with
// clockwise/anti-clockwise orbit gives at least 4 valid possibilities
// that need to handled.
//
// Additionaly this method implicitly includes the necessary adjustment
// to the manuever node position to account for the radial component
// of the ejection velocity.
//
// Finally it can handle non-perfectly circular and inclined orbits.
local function create_maneuver_node_in_correct_location {
    parameter origin, departure_time, departure_deltav.

    function ejection_details {
        parameter cost_only, v.

        local epoch_time is v:x.
        local osv is rsvp:orbital_state_vectors(ship, epoch_time).
        local ejection_deltav is rsvp:vessel_ejection_deltav_from_body(origin, osv, departure_deltav).

        return choose ejection_deltav:mag if cost_only else rsvp:maneuver_node_vector_projection(osv, ejection_deltav).
    }

    // Search for time in ship's orbit where ejection deltav is lowest.
    // Ejection velocity projected onto ship prograde, normal and radial vectors.
    local result is rsvp:coordinate_descent_1d(ejection_details@:bind(true), departure_time, 120, 1, 0.5).
    local projection is ejection_details(false, result:position).

    return create_then_add_node(result:position:x, projection).
}

local function create_then_add_node {
    parameter epoch_time, projection.

    local maneuver is node(epoch_time, projection:x, projection:y, projection:z).
    add maneuver.

    return maneuver.
}

local function distance_to_periapsis {
    parameter destination, maneuver, final_orbit_pe.

    local orbit is maneuver:orbit.

    until not orbit:hasnextpatch {
        set orbit to orbit:nextpatch.

        if orbit:body = destination {
            // Make sure orbit is prograde (even if only barely)
            // Inclination over 90 indicates a retrograde orbit.
            local sign is choose 1 if orbit:inclination < 90 else -1.
            local altitude is orbit:body:radius + orbit:periapsis.
            local desired is orbit:body:radius + final_orbit_pe.

            return abs(sign * altitude - desired).
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