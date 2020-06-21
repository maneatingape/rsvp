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
    local details is transfer_deltav(origin, destination, transfer:flip_direction, transfer:departure, transfer:arrival).

    local result is lexicon().
    result:add("success", true).
    result:add("departure", transfer:departure).
    result:add("arrival", transfer:arrival).
    result:add("total_deltav", transfer:total_deltav).
    result:add("prograde", details:prograde).
    result:add("radial", details:radial).
    result:add("normal", details:normal).
    result:add("dv1", details:dv1).
    result:add("dv2", details:dv2).
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

    function cost {
        parameter v.
        return vessel_ejection_deltav_from_origin(ship, details, v:x):mag.
    }

    local initial_position is v(details:departure, 0, 0).
    local initial_cost is cost(initial_position).
    local result is coordinate_descent_1d(cost@, initial_position, initial_cost, 120, 1, 0.5).

    local clock is result:position:x.
    local ejection is vessel_ejection_deltav_from_origin(ship, details, clock).

    // Ship prograde, normal and radial vectors
    local it1 is velocityat(ship, clock):orbit:normalized.
    local ir1 is (positionat(ship, clock) - ship:body:position):normalized.
    local ih1 is vcrs(it1, ir1):normalized.

    // Components of departure delta-v relative to origin direction.
    local prograde is vdot(it1, ejection).
    local radial is vdot(ir1, ejection).
    local normal is vdot(ih1, ejection).

    local maneuver is node(clock, radial, normal, prograde).
    add maneuver.
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

    local maneuver is node(details:departure, details:radial, details:normal, details:prograde).
    add maneuver.

    local function update_node {
        parameter v.
        set maneuver:radialout to v:x.
        set maneuver:normal to v:y.
        set maneuver:prograde to v:z.
    }

    local function intercept_distance {
        parameter v.
        update_node(v).
        return (positionat(origin, details:arrival) - positionat(destination, details:arrival)):mag.
    }

    local position is v(details:radial, details:normal, details:prograde).
    local refine is refine_maneuver_node(intercept_distance@, position).
    update_node(refine:position).

    local result is lexicon().
    result:add("success", true).
    result:add("arrival", details:arrival).
    result:add("arrival_deltav", details:dv2:mag).
    result:add("approximate_separation", refine:minimum).
    return result.
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