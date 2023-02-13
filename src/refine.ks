@lazyglobal off.

parameter export.
export("build_transfer_details", build_transfer_details@).

// Compose several orbital sub-functions to build the overall "cost" function
// used when searching the porkchop plot. The most important difference is
// between point-to-point transfers and soi-to-soi transfers.
//
// Point to point transfers treat the origin and destination as zero-width points
// and only use a single invocation of the Lamber solver for each point on the
// plot.
//
// SOI to SOI transfers take the spherical nature of the source and destination
// into account and run the Lambert solver multiple times, refining the position
// and time of the transfer for more accuracy. However as this is slower, it is
// only used when the ration of a body's SOI to its periapsis exceeds a threshold.
local function build_transfer_details {
    parameter origin, destination, settings.

    local from_vessel is settings:origin_type = "vessel".
    local to_vessel is settings:destination_type = "vessel".
    local initial_orbit_periapsis is max(ship:periapsis, 0).

    local transfer_deltav is rsvp:transfer_deltav:bind(origin, destination).
    local validate_ejection_orbit is build_validate_ejection_orbit(from_vessel).
    local validate_insertion_orbit is build_validate_insertion_orbit(to_vessel, destination, settings).
    local ejection_deltav is build_ejection_deltav(from_vessel, origin, initial_orbit_periapsis).
    local insertion_deltav is build_insertion_deltav(to_vessel, destination, settings).
    local success is build_success(ejection_deltav, insertion_deltav).

    if (from_vessel or below_soi_threshold(origin)) and (to_vessel or below_soi_threshold(destination)) {
        return build_point_to_point_transfer(transfer_deltav, validate_ejection_orbit, validate_insertion_orbit, success).
    }
    else {
        local adjust_departure is choose build_nop_adjustment(origin)
            if from_vessel else build_adjust_departure(origin, initial_orbit_periapsis).

        local adjust_arrival is choose build_nop_adjustment(destination)
            if to_vessel else build_adjust_arrival(destination, settings).

        return build_soi_to_soi_transfer(transfer_deltav, validate_ejection_orbit, validate_insertion_orbit, success, origin, adjust_departure, adjust_arrival).
    }
}

// Convenience method that returns a value indicating that the transfer
// is not possible, for example orbital constraints are breached or the
// iterative refinement failed to converge.
local function failure {
    return lex("ejection", "none", "insertion", "none").
}

// Check if a body's SOI to Periapsis ration is below a threshold of 1%.
// All planets except Jool in the stock game are under this threshold.
// All moons except Gilly and Pol are over this threshold.
local function below_soi_threshold {
    parameter destination_body.

    local ratio is destination_body:soiradius / destination_body:orbit:periapsis.

    return ratio < 0.01.
}

// Returns a delegate that validates transfer orbit constraints.
// Vessels are free to make any manuever no matter how small.
//
// Due to KSP's finite SOI, each celestial body has a deltav floor that a
// transfer cannot go below. For planets this doesn't matter too
// much, as the delta-v to the nearest neighbour will easily exceed this.
// However for moons with large SOI to Periapsis ratio, the minimum value can be
// high. For example a direct Hohmann transfer from Laythe to Vall is impossible
// as Laythe's minimum escape velocity is greater than this value.
local function build_validate_ejection_orbit {
    parameter from_vessel.

    if from_vessel {
        return {
            parameter details.
            return true.
        }.
    }
    else {
        // Apoapsis is the worse case scenario. Use this rather than periapsis,
        // as at this stage we don't know exactly where in the vessel's orbit
        // the departure manuever node will end up.
        local minimum_escape_velocity is rsvp:minimum_escape_velocity(ship:orbit:body, ship:orbit:apoapsis).

        return {
            parameter details.
            return details:dv1:mag > minimum_escape_velocity.
        }.
    }
}

// Similar to the previous function, returns a delegate that makes sure the
// injection orbit is above the minimum possible velocity based on the
// desired periapsis.
//
// This is to prevent errors when in some situtations the initial point to point
// transfer returned from the Lambert solver is below the minimum possible. 
local function build_validate_insertion_orbit {
    parameter to_vessel, destination, settings.

    if to_vessel {
        return {
            parameter details.
            return true.
        }.
    }
    else {
        // Minimum ejection and insertion values are the same due to the fact
        // orbits are symmetrical when direction is reversed.
        local minimum_insertion_velocity is rsvp:minimum_escape_velocity(destination, settings:final_orbit_periapsis).

        return {
            parameter details.
            return details:dv2:mag > minimum_insertion_velocity.
        }.
    }    
}

local function build_ejection_deltav {
    parameter from_vessel, origin, craft_altitude.

    local prefix is choose "vessel" if from_vessel else "equatorial".
    local delegate is rsvp[prefix + "_ejection_deltav"].

    return delegate:bind(origin, craft_altitude).
}

local function build_insertion_deltav {
    parameter to_vessel, destination, settings.

    local prefix is choose "vessel" if to_vessel else settings:final_orbit_type.
    local delegate is rsvp[prefix + "_insertion_deltav"].
    local final_orbit_periapsis is settings:final_orbit_periapsis.

    return delegate:bind(destination, final_orbit_periapsis).
}

// Combine the delegates returned by the previous two function into a single
// convenience delegate.
local function build_success {
    parameter ejection_deltav, insertion_deltav.

    return {
        parameter details.

        return lex(
            "ejection", ejection_deltav(details),
            "insertion", insertion_deltav(details:dv2)
        ).
    }.
}

// Vessels have no SOI and need no adjustment. Returns the same position and
// time that has been passed in.
local function build_nop_adjustment {
    parameter orbitable.

    return {
        parameter epoch_time, deltav.

        local osv is rsvp:orbital_state_vectors(orbitable, epoch_time).

        osv:add("adjusted_position", osv:position).
        osv:add("adjusted_time", epoch_time).

        return osv.
    }.
}

// Calculate the position where a vessel will exit the origin SOI and the
// duration of the journey from periapsis to edge of SOI, given a desired
// ejection velocity.
//
// One minor quirk, the orbit orientation is based on an injection trajectory,
// so a prograde ejection is a "retrograde" injection.
local function build_adjust_departure {
    parameter origin_body, craft_altitude.

    return {
        parameter epoch_time, deltav.

        local duration is rsvp:duration_from_soi_edge(origin_body, craft_altitude, deltav).
        local adjusted_time is epoch_time + duration.
        local osv is rsvp:orbital_state_vectors(origin_body, adjusted_time).
        local offset is rsvp:offset_from_soi_edge(origin_body, craft_altitude, "retrograde", deltav).

        osv:add("adjusted_position", osv:position + offset).
        osv:add("adjusted_time", adjusted_time).

        return osv.
    }.
}

// Calculate the position that a vessel should enter the SOI, in order to
// end up at the desired orientation and altitude.
local function build_adjust_arrival {
    parameter destination_body, settings.

    local craft_altitude is settings:final_orbit_periapsis.
    local orientation is settings:final_orbit_orientation.

    return {
        parameter epoch_time, deltav.

        local duration is rsvp:duration_from_soi_edge(destination_body, craft_altitude, deltav).
        local adjusted_time is epoch_time - duration.
        local osv is rsvp:orbital_state_vectors(destination_body, adjusted_time).
        local offset is rsvp:offset_from_soi_edge(destination_body, craft_altitude, orientation, deltav).

        osv:add("adjusted_position", osv:position + offset).
        osv:add("adjusted_time", adjusted_time).

        return osv.
    }.
}

// Point to point transfer neglecting the size of any SOIs.
local function build_point_to_point_transfer {
    parameter transfer_deltav, validate_ejection_orbit, validate_insertion_orbit, success.

    return {
        parameter flip_direction, departure_time, arrival_time.

        local details is transfer_deltav(flip_direction, departure_time, arrival_time).
        local validated is validate_ejection_orbit(details) and validate_insertion_orbit(details).

        return choose success(details) if validated else failure().
    }.
}

// Iteratively refine initial transfer in order to take SOI size into account.
local function build_soi_to_soi_transfer {
    parameter transfer_deltav, validate_ejection_orbit, validate_insertion_orbit, success, origin, adjust_departure, adjust_arrival.

    local mu is origin:body:mu.

    return {
        parameter flip_direction, departure_time, arrival_time.

        local details is transfer_deltav(flip_direction, departure_time, arrival_time).
        local validated is validate_ejection_orbit(details) and validate_insertion_orbit(details).

        if not validated {
            return failure().
        }

        local previous_delta is "max".
        local delta is 1.
        local iterations is 0.

        until delta < 1 {
            local departure is adjust_departure(departure_time, details:dv1).
            local arrival is adjust_arrival(arrival_time, details:dv2).

            local r1 is departure:adjusted_position.
            local r2 is arrival:adjusted_position.
            local time_of_flight is arrival:adjusted_time - departure:adjusted_time.

            local solution is rsvp:lambert(r1, r2, time_of_flight, mu, flip_direction).
            local dv1 is solution:v1 - departure:velocity.
            local dv2 is arrival:velocity - solution:v2.

            set delta to (details:dv1 - dv1):mag + (details:dv2 - dv2):mag.
            set details to lex("dv1", dv1, "dv2", dv2, "osv1", departure).
            set iterations to iterations + 1.
            set validated to validate_ejection_orbit(details) and validate_insertion_orbit(details).

            if iterations < 10 and delta < previous_delta and validated {
                set previous_delta to delta.
            }
            else {
                return failure().
            }
        }

        return success(details).
    }.
}