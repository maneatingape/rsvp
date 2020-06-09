@lazyglobal off.
runoncepath("kos-launch-window-finder/search.ks").

// Default value is 250, increase speed 8x as finding the lowest delta-v
// transfer is computationally intensive.
set config:ipu to 2000.

find_transfer(kerbin, duna).
find_transfer(kerbin, moho).
find_transfer(kerbin, eeloo).
find_transfer(laythe, tylo).

global function find_transfer {
    parameter origin, destination, options is lexicon().

    if origin:typename <> "body" return failure("Parameter 'origin' is not expected type Body").
    if destination:typename <> "body" return failure("Parameter 'destination' is not expected type Body").
    if options:typename <> "lexicon" return failure("Parameter 'options' is not expected type Lexicon").

    if origin = destination return failure("'origin' and 'destination' must be different bodies").
    if origin:body <> destination:body return failure("'origin' and 'destination' are not orbiting a direct common parent body").

    // Departure time
    local departure_time is -1.

    if not options:haskey("departure_time") {
        set departure_time to time():seconds.
    }
    else if options:departure_time:typename = "scalar" {
        set departure_time to options:departure_time.
        if departure_time < 0 return failure("Option 'departure_time' is negative").
    }
    else if options:departure_time:typename = "timespan" {
        set departure_time to options:departure_time:seconds.
        if departure_time < 0 return failure("Option 'departure_time' is negative").
    }
    else {
        return failure("Option 'departure_time' is not expected type of Scalar or TimeSpan").
    }

    // Initial orbit
    local initial_orbit is -1.

    if not options:haskey("initial_orbit") {
        set initial_orbit to 100000.
    }
    else if options:initial_orbit:typename = "scalar" {
        set initial_orbit to options:initial_orbit.
        if initial_orbit < 0 return failure("Option 'initial_orbit' is negative").
    }
    else {
        return failure("Option 'initial_orbit' is not expected type of Scalar").
    }

    // Final orbit type
    local final_orbit is -1.

    if not options:haskey("final_orbit_type") {
        set final_orbit to "circular".
    }
    else if option:final_orbit_type = "none" or option:final_orbit_type = "circular" or option:final_orbit_type = "elliptical" {
        set final_orbit to option:final_orbit_type.
    }
    else {
        return failure("Option 'final_orbit_type' is not one of expected values 'none', 'circular' or 'elliptical'").
    }

    // Final orbit periapsis
    local final_orbit_pe is -1.

    if not options:haskey("final_orbit_pe") {
        set final_orbit_pe to 100000.
    }
    else if options:final_orbit_pe:typename = "scalar" {
        set final_orbit_pe to options:final_orbit_pe.
        if final_orbit_pe < 0 return failure("Option 'final_orbit_pe' must be greater than or equal to zero").
    }
    else {
        return failure("Option 'final_orbit_pe' is not expected type Scalar").
    }

    // Maximum time of flight
    local max_time_of_flight is -1.

    if not options:haskey("max_time_of_flight") {
        set max_time_of_flight to "unlimited".
    }
    else if options:max_time_of_flight:typename = "scalar" {
        set max_time_of_flight to options:max_time_of_flight.
        if max_time_of_flight <= 0 return failure("Option 'max_time_of_flight' must be greater than zero").
    }
    else {
        return failure("Option 'max_time_of_flight' is not expected type Scalar").
    }

    // TODO:
    //search_duration: Default calculated
    // Vessel to vessel?
    // Impatience factor?
    
    local parent is origin:body.

    return iterated_hill_climb(parent, origin, destination).
}

local function success {
    parameter message.

    return lexicon("success", true, "message", message).
}

local function failure {
    parameter message.

    return lexicon("success", false, "message", message).
}