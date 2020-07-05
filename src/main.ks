@lazyglobal off.

parameter base_path is "0:/rsvp".

global rsvp is lexicon().

import("orbit.ks").
import("search.ks").
import("validate.ks").
import("lambert.ks").

export("find_launch_window", find_launch_window@).
export("vessel_to_vessel", vessel_to_vessel@).
export("vessel_to_planet", vessel_to_planet@).
export("planet_to_vessel", planet_to_vessel@).
export("planet_to_planet", planet_to_planet@).

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

        local details is transfer_details(flip_direction, departure_time, time_of_flight).
        return ejection_deltav(details) + insertion_deltav(details).
    }

    local transfer is rsvp:iterated_local_search(settings, total_deltav@).
    local details is transfer_details(transfer:flip_direction, transfer:departure_time, transfer:time_of_flight).

    return rsvp[settings:transfer_type](origin, destination, settings, transfer, details).
}

local function vessel_to_vessel {
    parameter origin, destination, settings, transfer, details.

    // If the destination is a vessel (including asteroids or comets) then our
    // intercept is already accurate enough and maneuver refinement has no benefit.
    if settings:create_maneuver_nodes <> "none" {
        local osv is rsvp:orbital_state_vectors(origin, transfer:departure_time).
        local initial_deltav is rsvp:maneuver_node_vector_projection(osv, details:dv1).
        create_then_add_node(transfer:departure_time, initial_deltav).
    }

    if settings:create_maneuver_nodes = "both" {
        local arrival_time is transfer:departure_time + transfer:time_of_flight.
        local osv is rsvp:orbital_state_vectors(origin, arrival_time).
        local final_deltav is rsvp:maneuver_node_vector_projection(osv, details:dv2).
        create_then_add_node(arrival_time, final_deltav).
    }

    return lexicon(
        "success", true,
        "departure_time", transfer:departure_time,
        "arrival_time", transfer:arrival_time,
        "total_deltav", transfer:total_deltav
    ).
}

local function vessel_to_planet {
    parameter origin, destination, settings, transfer, details.

    local departure_time is transfer:departure_time.
    local final_orbit_pe is settings:final_orbit_pe.
    local maneuver is 0.

    // For planets, our intercept is usually *too* accurate that it hits the planet
    // dead center, which is not usually what you want. So we tweak the intercept
    // in order to approximate the desired periapsis in a prograde direction.
    if settings:create_maneuver_nodes <> "none" {
        local osv is rsvp:orbital_state_vectors(origin, departure_time).
        local initial_deltav is rsvp:maneuver_node_vector_projection(osv, details:dv1).
        set maneuver to create_then_add_node(departure_time, initial_deltav).

        refine_maneuver_node_time(destination, maneuver, final_orbit_pe, departure_time).
        vessel_refine_maneuver_node_deltav(destination, maneuver, final_orbit_pe, initial_deltav).
    }

    if settings:create_maneuver_nodes = "both" {
        local arrival_time is time_to_periapsis(destination, maneuver).
        // TODO: Use actual velocity of vessel at that point.
        // TODO: Use actual desired function
        local deltav is rsvp:circular_insertion_deltav(destination, final_orbit_pe, details).
        create_then_add_node(arrival_time, v(0, 0, -deltav)).
    }

    return lexicon("success", true).
}

local function planet_to_vessel {
    parameter origin, destination, settings, transfer, details.

    return lexicon("sucess", false, "message", "Planet to Vessel is not supported yet").
}

local function planet_to_planet {
    parameter origin, destination, settings, transfer, details.

    // Creates maneuver node at the correct location around the origin
    // planet in order to eject at the desired orientation.
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
    //
    // TODO: Re-calculate transfer details?
    function cost {
        parameter v.
        local osv is rsvp:orbital_state_vectors(ship, v:x).
        return rsvp:vessel_ejection_deltav_from_origin(origin, osv, details):mag.
    }

    local initial_position is v(transfer:departure_time, 0, 0).
    local initial_cost is cost(initial_position).
    local result is rsvp:coordinate_descent_1d(cost@, initial_position, initial_cost, 120, 1, 0.5).

    local refined_time is result:position:x.
    local osv is rsvp:orbital_state_vectors(ship, refined_time).
    local ejection_velocity is rsvp:vessel_ejection_deltav_from_origin(origin, osv, details).

    // Ejection velocity projected onto ship prograde, normal and radial vectors.
    local projection is rsvp:maneuver_node_vector_projection(osv, ejection_velocity).

    if settings:create_maneuver_nodes <> "none" {
        local maneuver is create_then_add_node(refined_time, projection).
        refine_maneuver_node_time(destination, maneuver, settings:final_orbit_pe, refined_time).
    }

    return lexicon("success", true).
}

// Applies coordinate descent algorithm in 1 dimension (time)
// to refine initial manuever node and get a closer intercept.
local function refine_maneuver_node_time {
    parameter destination, maneuver, final_orbit_pe, departure_time.

    function cost {
        parameter new_time.
        update_node_time(maneuver, new_time:x).
        return distance_to_periapsis(destination, maneuver, final_orbit_pe).
    }

    local initial_position is v(departure_time, 0, 0).
    local initial_cost is cost(initial_position).
    local result is rsvp:coordinate_descent_1d(cost@, initial_position, initial_cost, 120, 1, 0.5).

    update_node_time(maneuver, result:position:x).
}

// Applies coordinate descent algorithm in 3 dimensions (prograde, radial and normal)
// to refine initial manuever node and get a closer intercept.
local function vessel_refine_maneuver_node_deltav {
    parameter destination, maneuver, final_orbit_pe, initial_deltav.

    local function cost {
        parameter new_deltav.
        update_node_deltav(maneuver, new_deltav).
        return distance_to_periapsis(destination, maneuver, final_orbit_pe).
    }
    
    local initial_cost is cost(initial_deltav).
    local result is rsvp:coordinate_descent_3d(cost@, initial_deltav, initial_cost, 1, 0.001, 0.5).

    update_node_deltav(maneuver, result:position).
}

local function create_then_add_node {
    parameter epoch_time, projection.

    local maneuver is node(epoch_time, projection:x, projection:y, projection:z).
    add maneuver.

    return maneuver.
}

local function update_node_time {
    parameter maneuver, epoch_time.

    set maneuver:eta to epoch_time - time():seconds.

    // Waiting until next physics tick "animates" the refinement steps
    wait 0.
}

local function update_node_deltav {
    parameter node, projection.

    set node:radialout to projection:x.
    set node:normal to projection:y.
    set node:prograde to projection:z.

    // Waiting until next physics tick "animates" the refinement steps
    wait 0.
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
            return time:seconds() + (start + end) / 2.
        }
    }
    
    return "max".    
}