@lazyglobal off.

parameter export.
export("find_launch_window", find_launch_window@).

local function find_launch_window {
    parameter destination, options is lexicon().

    local result is rsvp:validate_parameters(destination, options).

    if not result:success {
        print result:value.
        return result.
    }

    local settings is result:value.
    local transfer is find_transfer(destination, settings).

    set result to lexicon().
    result:add("success", true).
    result:add("estimated_departure_time", transfer:departure_time).
    result:add("estimated_arrival_time", transfer:arrival_time).
    result:add("estimated_total_deltav", transfer:total_deltav).

    // First check point. If no nodes are requests then we're done.
    if settings:create_maneuver_nodes = "none" return result.

    local maneuver is from_origin(destination, settings, transfer, v(0, 0, 0)).

    // If the destination is a vessel (including asteroids or comets) then our
    // intercept is already accurate enough and maneuver refinement has no benefit.
    //
    // For planets, our intercept is usually *too* accurate that it hits the planet
    // dead center, which is not usually what you want. So we tweak the intercept
    // in order to approximate the desired periapsis in a prograde direction.
    if destination:istype("body") {
        if settings:origin_is_body {
            local arrival is maneuver:osv_at_destination_soi().
        
            if arrival:success {
                local offset is rsvp:impact_parameter_offset(destination, arrival:time, arrival:velocity, settings:final_orbit_periapsis, settings:final_orbit_orientation).
                maneuver:delete().
                set maneuver to from_origin(destination, settings, transfer, offset:factor * offset:vector).
            }

        }
        else {
            local arrival is maneuver:osv_at_destination_soi().
            local offset is rsvp:impact_parameter_offset(destination, arrival:time, arrival:velocity, settings:final_orbit_periapsis, settings:final_orbit_orientation).

            function cost {
                parameter v.

                maneuver:delete().
                set maneuver to from_origin(destination, settings, transfer, v:x * offset:vector).

                return maneuver:distance_to_periapsis(settings:final_orbit_periapsis).
            }

            local result is rsvp:line_search(cost@, offset:factor, 0.25 * offset:factor, 100, 0.5).
            cost(result:position).
        }

        if settings:create_maneuver_nodes = "both" {
            local arrival is maneuver:osv_at_destination_soi().
            local periapsis_details is maneuver:time_to_periapsis().

            if periapsis_details <> "max" {
                // TODO: Move to "maneuver.ks"
                local foo is lexicon("dv2", arrival:velocity).
                local bar is get_insertion_deltav_function(destination, settings).
                local qux is bar(destination, periapsis_details:altitude, foo).

                add node(periapsis_details:time, 0, 0, -qux).
            }
            else {
                // TODO: Handle error case.
            }
        }        
    }

    result:add("actual_departure_time", maneuver:departure_time()).
    result:add("actual_ejection_deltav", maneuver:deltav()).

    return result.
}

local function find_transfer {
    parameter destination, settings.

    local origin is choose ship:body if settings:origin_is_body else ship.

    local verbose is settings:verbose.

    local earliest_departure is settings:earliest_departure.
    if earliest_departure = "default" {
        set earliest_departure to time():seconds + 120.
    }

    local search_duration is settings:search_duration.
    if search_duration = "default" {
        local max_period is rsvp:max_period(origin, destination).
        local synodic_period is rsvp:synodic_period(origin, destination).
        set search_duration to max(max_period, synodic_period).
    }

    local max_time_of_flight is settings:max_time_of_flight.
    if max_time_of_flight = "default" {
        set max_time_of_flight to rsvp:ideal_hohmann_transfer_period(origin, destination).
    }

    local min_period is rsvp:min_period(origin, destination).
    local search_interval is 0.5 * min_period.
    local search_threshold is max(120, min(0.001 * min_period, 3600)).

    local transfer_details is rsvp:transfer_deltav:bind(origin, destination).
    local ejection_deltav is choose rsvp:equatorial_ejection_deltav if settings:origin_is_body else rsvp:vessel_ejection_deltav.
    
    local initial_orbit_periapsis is max(ship:periapsis, 0).
    local final_orbit_periapsis is settings:final_orbit_periapsis.

    local insertion_deltav is get_insertion_deltav_function(destination, settings).

    function total_deltav {
        parameter flip_direction, departure_time, time_of_flight.

        local arrival_time is departure_time + time_of_flight.
        local details is transfer_details(flip_direction, departure_time, arrival_time).
        local ejection is ejection_deltav(origin, initial_orbit_periapsis, details).
        local insertion is insertion_deltav(destination, final_orbit_periapsis, details).

        return ejection + insertion.
    }

    return rsvp:iterated_local_search(verbose, earliest_departure, search_duration, max_time_of_flight, search_interval, search_threshold, total_deltav@).
}

local function get_insertion_deltav_function {
    parameter destination, settings.

    local key is choose settings:final_orbit_type if destination:istype("body") else "vessel".
    local values is lexicon(
        "vessel", rsvp:vessel_insertion_deltav,
        "circular", rsvp:circular_insertion_deltav,
        "elliptical", rsvp:elliptical_insertion_deltav,
        "none", rsvp:no_insertion_deltav
    ).

    return values[key].
}

local function from_origin {
    parameter destination, settings, transfer, offset.

    local flip_direction is transfer:flip_direction.
    local departure_time is transfer:departure_time.
    local arrival_time is transfer:arrival_time.

    if settings:origin_is_body {
        return from_body(destination, flip_direction, departure_time, arrival_time, offset).
    }
    else {
        return from_vessel(destination, flip_direction, departure_time, arrival_time, offset).
    }
}

local function from_vessel {
    parameter destination, flip_direction, departure_time, arrival_time, offset.

    local details is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time, ship:body, offset).
    local osv is rsvp:orbital_state_vectors(ship, departure_time).
    local projection is rsvp:maneuver_node_vector_projection(osv, details:dv1).

    return rsvp:create_maneuver(destination, departure_time, projection).
}

local function from_body {
    parameter destination, flip_direction, departure_time, arrival_time, offset.

    local delta is v(1, 0, 0).
    local iterations is 0.

    // TODO: flip_direction can't be trusted
    local details is rsvp:transfer_deltav(ship:body, destination, flip_direction, departure_time, arrival_time, ship:body:body, offset).
    local departure_deltav is details:dv1.
    local maneuver is create_maneuver_node_in_correct_location(destination, departure_time, departure_deltav).

    until delta:mag < 0.001 or iterations = 15 {
        local patch_time is maneuver:patch_time().
        local details is rsvp:transfer_deltav(ship, destination, flip_direction, patch_time, arrival_time, ship:body:body, offset).

        set delta to details:dv1.
        set iterations to iterations + 1.
        set departure_time to maneuver:departure_time().
        set departure_deltav to departure_deltav + delta.

        maneuver:delete().
        set maneuver to create_maneuver_node_in_correct_location(destination, departure_time, departure_deltav).
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
    parameter destination, departure_time, departure_deltav.

    function ejection_details {
        parameter cost_only, v.

        local epoch_time is v:x.
        local osv is rsvp:orbital_state_vectors(ship, epoch_time).
        local ejection_deltav is rsvp:vessel_ejection_deltav_from_body(ship:body, osv, departure_deltav).

        return choose ejection_deltav:mag if cost_only else rsvp:maneuver_node_vector_projection(osv, ejection_deltav).
    }

    // Search for time in ship's orbit where ejection deltav is lowest.
    // Ejection velocity projected onto ship prograde, normal and radial vectors.
    local result is rsvp:line_search(ejection_details@:bind(true), departure_time, 120, 1, 0.5).
    local projection is ejection_details(false, result:position).

    return rsvp:create_maneuver(destination, result:position:x, projection).
}