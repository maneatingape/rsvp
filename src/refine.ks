@lazyglobal off.

parameter export.
export("build_transfer_details", build_transfer_details@).

local function build_transfer_details {
    parameter origin, destination, settings.

    local from_vessel is settings:origin_type = "vessel".
    local to_vessel is settings:destination_type = "vessel".
    local initial_orbit_periapsis is max(ship:periapsis, 0).

    // Compose orbital functions.
    local transfer_deltav is rsvp:transfer_deltav:bind(origin, destination).
    local validate_orbit is build_validate_orbit(from_vessel).
    local ejection_deltav is build_ejection_deltav(from_vessel, origin, initial_orbit_periapsis).
    local insertion_deltav is build_insertion_deltav(to_vessel, destination, settings).
    local success is build_success(ejection_deltav, insertion_deltav).

    if (from_vessel or below_soi_threshold(origin)) and (to_vessel or below_soi_threshold(destination)) {
        return build_point_to_point_transfer(transfer_deltav, validate_orbit, success).
    }
    else {
        local adjust_departure is choose build_nop_adjustment(origin)
            if from_vessel else build_adjust_departure(origin, initial_orbit_periapsis).

        local adjust_arrival is choose build_nop_adjustment(destination)
            if to_vessel else build_adjust_arrival(destination, settings).

        return build_soi_to_soi_transfer(transfer_deltav, validate_orbit, success, origin, adjust_departure, adjust_arrival).
    }
}

local function build_validate_orbit {
    parameter from_vessel.

    if from_vessel {
        return {
            parameter details.
            return true.
        }.
    }
    else {
        local minimum_escape_velocity is rsvp:minimum_escape_velocity(ship:orbit).

        return {
            parameter details.
            return details:dv1:mag > minimum_escape_velocity.
        }.
    }
}

local function build_ejection_deltav {
    parameter from_vessel, origin, altitude.

    local prefix is choose "vessel" if from_vessel else "equatorial".
    local delegate is rsvp[prefix + "_ejection_deltav"].

    return delegate:bind(origin, altitude).
}

local function build_insertion_deltav {
    parameter to_vessel, destination, settings.

    local prefix is choose "vessel" if to_vessel else settings:final_orbit_type.
    local delegate is rsvp[prefix + "_insertion_deltav"].
    local final_orbit_periapsis is settings:final_orbit_periapsis.

    return delegate:bind(destination, final_orbit_periapsis).
}

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

local function failure {
    return lex("ejection", "none", "insertion", "none").
}

local function below_soi_threshold {
    parameter body.

    local ratio is body:soiradius / body:orbit:periapsis.

    return ratio < 0.01.
}

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

local function build_adjust_departure {
    parameter body, altitude.

    return {
        parameter epoch_time, deltav.

        local duration is rsvp:duration_from_soi_edge(body, altitude, deltav).
        local adjusted_time is epoch_time + duration.
        local osv is rsvp:orbital_state_vectors(body, adjusted_time).
        local offset is rsvp:offset_from_soi_edge(body, altitude, "retrograde", deltav).

        osv:add("adjusted_position", osv:position + offset).
        osv:add("adjusted_time", adjusted_time).

        return osv.
    }.
}

local function build_adjust_arrival {
    parameter body, settings.

    local altitude is settings:final_orbit_periapsis.
    local orientation is settings:final_orbit_orientation.

    return {
        parameter epoch_time, deltav.

        local duration is rsvp:duration_from_soi_edge(body, altitude, deltav).
        local adjusted_time is epoch_time - duration.
        local osv is rsvp:orbital_state_vectors(body, adjusted_time).
        local offset is rsvp:offset_from_soi_edge(body, altitude, orientation, deltav).

        osv:add("adjusted_position", osv:position + offset).
        osv:add("adjusted_time", adjusted_time).

        return osv.
    }.
}

local function build_point_to_point_transfer {
    parameter transfer_deltav, validate_orbit, success.

    return {
        parameter flip_direction, departure_time, arrival_time.

        local details is transfer_deltav(flip_direction, departure_time, arrival_time).

        return choose success(details) if validate_orbit(details) else failure().
    }.
}

local function build_soi_to_soi_transfer {
    parameter transfer_deltav, validate_orbit, success, origin, adjust_departure, adjust_arrival.

    local mu is origin:body:mu.

    return {
        parameter flip_direction, departure_time, arrival_time.

        local details is transfer_deltav(flip_direction, departure_time, arrival_time).

        if not validate_orbit(details) {
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

            if iterations < 10 and delta < previous_delta and validate_orbit(details) {
                set previous_delta to delta.
            }
            else {
                return failure().
            }
        }

        return success(details).
    }.
}