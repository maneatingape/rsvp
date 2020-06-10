@lazyglobal off.
runoncepath("kos-launch-window-finder/orbit.ks").
runoncepath("kos-launch-window-finder/search.ks").

global function find_launch_window {
    parameter origin, destination, options is lexicon().

    if not (is_body(origin) or is_vessel(origin)) {
        return failure("'origin' is not expected type Body or Vessel").
    }
    else if not (is_body(destination) or is_vessel(destination)) {
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
    local departure_time is time():seconds.

    if options:haskey("departure_time") {
        if is_scalar(options:departure_time) {
            set departure_time to options:departure_time.
        }
        else if is_timespan(options:departure_time) {
            set departure_time to options:departure_time:seconds.
        }
        else {
            return failure("'departure_time' is not expected type Scalar or TimeSpan").
        }

        if departure_time < 0 {
            return failure("'departure_time' must be greater than or equal to zero").
        }
    }

    // Search duration
    local search_duration is max(synodic_period(origin, destination), max(origin:orbit:period, destination:orbit:period)).

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
    local max_time_of_flight is 2 * ideal_hohmann_transfer_tof(origin, destination).

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
    local ejection_deltav is choose equatorial_ejection_deltav@ if is_body(origin) else vessel_rendezvous_deltav@.

    // Initial orbit periapsis
    local initial_orbit_pe is 100000.

    if options:haskey("initial_orbit_pe") {
        if is_vessel(origin) {
            return failure("'initial_orbit_pe' is not applicable to Vessel").
        }    
        else if is_scalar(options:initial_orbit_pe) {
            set initial_orbit_pe to options:initial_orbit_pe.
        }
        else if options:initial_orbit_pe = "min" {
            set initial_orbit_pe to choose origin:atm:height + 10000 if origin:atm:exists else 10000.
        }
        else {
            return failure("'initial_orbit_pe' is not expected type Scalar or special value 'min'").
        }

        if initial_orbit_pe < 0 {
            return failure("'initial_orbit_pe' must be greater than or equal to zero").
        }
    }

    // Final orbit type
    local insertion_deltav is choose circular_insertion_deltav@ if is_body(destination) else vessel_rendezvous_deltav@.

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

    // TODO:
    // Verbose?
    // Impatience factor?
    // Inclined orbit ejection?

    // Put it all together
    local total_deltav is {
        parameter flip_direction, t1, t2.

        local solution is transfer_deltav(origin, destination, flip_direction, t1, t2).
        local ejection is ejection_deltav(origin, initial_orbit_pe, solution:dv1).
        local insertion is insertion_deltav(destination, final_orbit_pe, solution:dv2).

        return ejection + insertion.
    }.

    local step is min(origin:orbit:period, destination:orbit:period).

    print "=======".
    print origin:name + " => " + destination:name.
    return iterated_hill_climb(total_deltav, departure_time, search_duration, max_time_of_flight, step).
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