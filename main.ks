@lazyglobal off.
runoncepath("0:/rsvp/orbit.ks").
runoncepath("0:/rsvp/search.ks").

global function find_launch_window {
    parameter origin, destination, options is lexicon().

    if not (is_body(origin) or is_vessel(origin)) {
        return failure("'origin' is not expected type Body or Vessel").
    }
    if not (is_body(destination) or is_vessel(destination)) {
        return failure("'destination' is not expected type Body or Vessel").
    }
    if not is_lexicon(options) {
        return failure("'options' is not expected type Lexicon").
    }
    if origin = destination {
        return failure("'origin' and 'destination' must be different").
    }
    if origin:body <> destination:body {
        return failure("'origin' and 'destination' are not orbiting a direct common parent body").
    }

    // Departure time
    local earliest_departure is time():seconds.

    if options:haskey("earliest_departure") {
        if is_scalar(options:earliest_departure) {
            set earliest_departure to options:earliest_departure.
        }
        else if is_timespan(options:earliest_departure) {
            set earliest_departure to options:earliest_departure:seconds.
        }
        else {
            return failure("'earliest_departure' is not expected type Scalar or TimeSpan").
        }

        if earliest_departure < 0 {
            return failure("'earliest_departure' must be greater than or equal to zero").
        }
    }

    // Search duration
    local search_duration is max(max_period(origin, destination), synodic_period(origin, destination)).

    if options:haskey("search_duration") {
        if is_scalar(options:search_duration) {
            set search_duration to options:search_duration.
        }
        else {
            return failure("'search_duration' is not expected type Scalar").
        }

        if search_duration <= 0 {
            return failure("'search_duration' must be greater than zero").
        }
    }

    // Maximum time of flight
    local max_time_of_flight is ideal_hohmann_transfer_period(origin, destination).

    if options:haskey("max_time_of_flight") {
        if is_scalar(options:max_time_of_flight) {
            set max_time_of_flight to options:max_time_of_flight.
        }
        else {
            return failure("'max_time_of_flight' is not expected type Scalar").
        }

        if max_time_of_flight <= 0 {
            return failure("'max_time_of_flight' must be greater than zero").
        }
    }

    // Initial orbit type always "equatorial" for now
    local ejection_deltav is choose equatorial_ejection_deltav@ if is_body(origin) else vessel_ejection_deltav@.

    // Initial orbit periapsis
    local initial_orbit_altitude is 100000.

    if options:haskey("initial_orbit_altitude") {
        if is_vessel(origin) {
            return failure("'initial_orbit_altitude' is not applicable to Vessel").
        }
        else if is_scalar(options:initial_orbit_altitude) {
            set initial_orbit_altitude to options:initial_orbit_altitude.
        }
        else if options:initial_orbit_altitude = "min" {
            set initial_orbit_altitude to choose origin:atm:height + 10000 if origin:atm:exists else 10000.
        }
        else {
            return failure("'initial_orbit_altitude' is not expected type Scalar or special value 'min'").
        }

        if initial_orbit_altitude < 0 {
            return failure("'initial_orbit_altitude' must be greater than or equal to zero").
        }
    }

    // Final orbit type
    local insertion_deltav is choose circular_insertion_deltav@ if is_body(destination) else vessel_insertion_deltav@.

    if options:haskey("final_orbit_type") {
        if is_vessel(destination) {
            return failure("'final_orbit_type' is not applicable to Vessel").
        }
        else if option:final_orbit_type = "none" {
            set insertion_deltav to no_insertion_deltav@.
        }
        else if option:final_orbit_type = "circular" {
            set insertion_deltav to circular_insertion_deltav@.
        }
        else if option:final_orbit_type = "elliptical" {
            set insertion_deltav to elliptical_insertion_deltav@.
        }
        else {
            return failure("'final_orbit_type' is not one of expected values 'none', 'circular' or 'elliptical'").
        }
    }

    // Final orbit periapsis
    local final_orbit_pe is 100000.

    if options:haskey("final_orbit_pe") {
        if is_vessel(origin) {
            return failure("'final_orbit_pe' is not applicable to Vessel").
        }
        else if is_scalar(options:final_orbit_pe) {
            set final_orbit_pe to options:final_orbit_pe.
        }
        else if options:final_orbit_pe = "min" {
            set final_orbit_pe to choose destination:atm:height + 10000 if destination:atm:exists else 10000.
        }
        else {
            return failure("'final_orbit_pe' is not expected type Scalar or special value 'min'").
        }

        if final_orbit_pe < 0 {
            return failure("'final_orbit_pe' must be greater than or equal to zero").
        }
    }

    // Verbose mode prints detailed information to the console
    local verbose is false.

    if options:haskey("verbose") {
        if is_boolean(options:verbose) {
            set verbose to options:verbose.
        }
        else {
            return failure("'verbose' is not expected type Boolean").
        }
    }

    // Compose settings into a single cost function
    local latest_departure is earliest_departure + search_duration.
    local search_interval is 0.5 * min_period(origin, destination).
    local threshold is choose 3600 if is_body(origin) else 60.

    local function total_deltav {
        parameter flip_direction, departure_time, time_of_flight.

        local details is transfer_deltav(origin, destination, flip_direction, departure_time, departure_time + time_of_flight).
        local ejection is ejection_deltav(origin, initial_orbit_altitude, details).
        local insertion is insertion_deltav(destination, final_orbit_pe, details).

        return ejection + insertion.
    }

    if verbose {
        print "Details".
        print "  Origin: " + origin:name.
        print "  Destination: " + destination:name.
        print "  Earliest Departure: " + seconds_to_kerbin_time(earliest_departure).
        print "  Latest Departure: " + seconds_to_kerbin_time(latest_departure).
    }

    local transfer is iterated_local_search(earliest_departure, latest_departure, search_interval, threshold, max_time_of_flight, total_deltav@, verbose).
    local details is transfer_deltav(origin, destination, transfer:flip_direction, transfer:departure_time, transfer:arrival_time).

    local result is lexicon().
    result:add("success", true).
    result:add("departure_time", transfer:departure_time).
    result:add("arrival_time", transfer:arrival_time).
    result:add("total_deltav", transfer:total_deltav).
    result:add("dv1", details:dv1).
    result:add("dv2", details:dv2).
    result:add("osv1", details:osv1).
    return result.
}

// WORK IN PROGRESS
// Creates maneuver node at the correct location around the origin
// planet in order to eject at the desired orientation.
global function body_create_maneuver_node {
    parameter origin, destination, options is lexicon().

    local details is find_launch_window(origin, destination, options).
    if not details:success return details.
    if hasnode return failure("Existing maneuver nodes already exist.").

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
        local osv is orbital_state_vectors(ship, v:x).
        return vessel_ejection_deltav_from_origin(origin, osv, details):mag.
    }

    local initial_position is v(details:departure_time, 0, 0).
    local initial_cost is cost(initial_position).
    local result is coordinate_descent_1d(cost@, initial_position, initial_cost, 120, 1, 0.5).

    local refined_time is result:position:x.
    local osv is orbital_state_vectors(ship, refined_time).
    local ejection_velocity is vessel_ejection_deltav_from_origin(origin, osv, details).

    // Ejection velocity projected onto ship prograde, normal and radial vectors.
    local projection is maneuver_node_vector_projection(osv, ejection_velocity).

    local maneuver is create_then_add_node(refined_time, projection).
    body_refine_maneuver_node_time(maneuver, refined_time, destination).
}

local function body_refine_maneuver_node_time {
    parameter maneuver, epoch_time, destination.

    function cost {
        parameter new_time.
        update_node_time(maneuver, new_time:x).
        return body_distance(destination, maneuver).
    }

    local initial_position is v(epoch_time, 0, 0).
    local initial_cost is cost(initial_position).
    local result is coordinate_descent_1d(cost@, initial_position, initial_cost, 120, 1, 0.5).

    update_node_time(maneuver, result:position:x).
}

// WORK IN PROGRESS
// Only works when both origin and destination are vessels.
// Applies coordinate descent algorithm in 3 dimensions (prograde, radial and normal)
// to refine initial manuever node and get a closer intercept.
global function vessel_create_maneuver_nodes {
    parameter origin, destination, options is lexicon().

    local details is find_launch_window(origin, destination, options).
    if not details:success return details.
    if hasnode return failure("Existing maneuver nodes already exist.").

    local osv is orbital_state_vectors(origin, details:departure_time).
    local projection is maneuver_node_vector_projection(osv, details:dv1).
    local maneuver is create_then_add_node(details:departure_time, projection).
    local separation is vessel_distance(origin, destination, details:arrival_time).

    local result is lexicon().
    result:add("success", true).
    result:add("arrival_time", details:arrival_time).
    result:add("arrival_deltav", details:dv2:mag).
    result:add("arrival_separation", separation).
    return result.
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
}

local function update_node_deltav {
    parameter node, projection.

    set node:radialout to projection:x.
    set node:normal to projection:y.
    set node:prograde to projection:z.
}

local function body_distance {
    parameter destination, maneuver.

    local patch is maneuver:orbit.

    until not patch:hasnextpatch {
        set patch to patch:nextpatch.

        if patch:body = destination {
            return abs(100000 - patch:periapsis).
        }
    }

    return "max".
}

local function vessel_distance {
    parameter origin, destination, epoch_time.

    return (positionat(origin, epoch_time) - positionat(destination, epoch_time)):mag.
}

local function failure {
    parameter message.
    return lexicon("success", false, "message", message).
}

local function is_type {
    parameter type, x.
    return type = x:typename.
}

local is_body is is_type@:bind("body").
local is_vessel is is_type@:bind("vessel").
local is_lexicon is is_type@:bind("lexicon").
local is_scalar is is_type@:bind("scalar").
local is_timespan is is_type@:bind("timespan").
local is_boolean is is_type@:bind("boolean").