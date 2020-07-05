@lazyglobal off.

parameter export.
export("validate_parameters", validate_parameters@).

local is_body is is_type@:bind("body").
local is_vessel is is_type@:bind("vessel").
local is_lexicon is is_type@:bind("lexicon").
local is_scalar is is_type@:bind("scalar").
local is_timespan is is_type@:bind("timespan").
local is_boolean is is_type@:bind("boolean").

local delegates is lexicon(
    "earliest_departure", list(validate_earliest_departure@, default_earliest_departure@),
    "search_duration", list(validate_search_duration@, default_search_duration@),
    "max_time_of_flight", list(validate_max_time_of_flight@, default_max_time_of_flight@),
    "initial_orbit_type", list(validate_initial_orbit_type@, default_initial_orbit_type@),
    "initial_orbit_pe", list(validate_initial_orbit_pe@, default_initial_orbit_pe@),
    "final_orbit_type", list(validate_final_orbit_type@, default_final_orbit_type@),
    "final_orbit_pe", list(validate_final_orbit_pe@, default_final_orbit_pe@),
    "create_maneuver_nodes", list(validate_create_maneuver_nodes@, default_create_maneuver_nodes@),
    "verbose", list(validate_verbose@, default_verbose@)    
).

local function validate_parameters {
    parameter origin, destination, options.

    // Collect valid options into "settings" and error messages into "problems".
    local settings is lexicon().
    local problems is lexicon().

    function setting {
        parameter key.
        return {
            parameter value.
            settings:add(key, value).
            return value.
        }.
    }

    function problem {
        parameter key, value.
        problems:add(key, value).
    }

    // Normally we'll try to gather as many problems before returning
    // but problems here are showstoppers that mean we can't continue.
    validate_parameter_types(origin, destination, options, problem@).
    if problems:length > 0 return failure(problems).

    validate_orbital_constraints(origin, destination, setting("transfer_type"), problem@).
    if problems:length > 0 return failure(problems).

    // Check for unknown option keys that could indicate a typo
    for key in options:keys {
        if not delegates:haskey(key) {
            problem(9, "Option '" + key + "' is not recognised").
        }
    }

    // Use either provided option for each setting or calculate sensible default
    for key in delegates:keys {
        local validate_option is delegates[key][0].
        local provide_default is delegates[key][1].

        if options:haskey(key) {
            validate_option(origin, destination, options[key], setting(key), problem@).
        }
        else {
            setting(key)(provide_default(origin, destination)).
        }
    }

    return choose success(settings) if problems:length = 0 else failure(problems).
}

// Basic sanity check of parameter types
local function validate_parameter_types {
    parameter origin, destination, options, problem.

    if not is_body(origin) and not is_vessel(origin) {
        problem(1, "Parameter 'origin' is not expected type Orbitable (Vessels and Bodies)").
    }
    if not is_body(destination) and not is_vessel(destination) {
        problem(2, "Parameter 'destination' is not expected type Orbitable (Vessels and Bodies)").
    }
    if not is_lexicon(options) {
        problem(3, "Parameter 'options' is not expected type Lexicon").
    }
}

// Sanity check origin and destination
local function validate_orbital_constraints {
    parameter origin, destination, setting, problem.

    if origin = destination {
        problem(4, "'origin' and 'destination' must be different").
    }
    if not origin:hasbody {
        problem(5, "Origin '" + origin:name + "' is not orbiting a parent body.").
    }    
    if not destination:hasbody {
        problem(6, "Destination '" + origin:name + "' is not orbiting a parent body.").
    }

    local ancestors is origin:hasbody and destination:hasbody.
    local parent is ancestors and origin:body = destination:body.
    local grandparent is ancestors and origin:body:hasbody and origin:body:body = destination:body.

    if is_body(origin) {
        if parent {
            setting("info").
        }
        else {
            problem(7, "Destination '" + destination:name + "' is not orbiting a direct common parent of origin '" + origin:name + "'").
        }
    }
    else {
        if parent {
            local transfer_type is choose "vessel_to_planet" if is_body(destination) else "vessel_to_vessel".
            setting(transfer_type).
        }
        else if grandparent {
            local transfer_type is choose "planet_to_planet" if is_body(destination) else "planet_to_vessel".
            setting(transfer_type).
        }
        else {
            problem(8, "Destination '" + destination:name + "' is not orbiting a direct common parent or grandparent of origin '" + origin:name + "'").    
        }
    }
}

local function validate_earliest_departure {
    parameter origin, destination, value, setting, problem.

    if is_scalar(value) {
        if setting(value) < 0 {
            problem(10, "'earliest_departure' must be greater than or equal to zero").
        }    
    }
    else if is_timespan(value) {
        if setting(value:seconds) < 0 {
            problem(10, "'earliest_departure' must be greater than or equal to zero").
        }            
    }
    else {
        problem(11, "'earliest_departure' is not expected type Scalar or TimeSpan").
    }
}

local function validate_search_duration {
    parameter origin, destination, value, setting, problem.

    if is_scalar(value) {                
        if setting(value) {
            problem(12, "'search_duration' must be greater than zero").
        }    
    }
    else {
        problem(13, "'search_duration' is not expected type Scalar").
    }
}

local function validate_max_time_of_flight {
    parameter origin, destination, value, setting, problem.

    if is_scalar(value) {
        if setting(value) <= 0 {
            problem(14, "'max_time_of_flight' must be greater than zero").
        }    
    }
    else {
        problem(15, "'max_time_of_flight' is not expected type Scalar").
    }
}

local function validate_initial_orbit_type {
    parameter origin, destination, value, setting, problem.

    problems(16, "'initial_orbit_type' is not user-definable").
}

local function validate_initial_orbit_pe {
    parameter origin, destination, value, setting, problem.

    if is_vessel(origin) {
        problem(17, "'initial_orbit_pe' is not applicable to Vessel").
    }
    else if is_scalar(value) {
        if setting(value) < 0 {
            problem(18, "'initial_orbit_pe' must be greater than or equal to zero").
        }            
    }
    else if value = "min" {
        local altitude is choose origin:atm:height + 10000 if origin:atm:exists else 10000.
        setting(altitude).
    }
    else {
        problems:add(19, "'initial_orbit_pe' is not expected type Scalar or special value 'min'").
    }
}

local function validate_final_orbit_type {
    parameter origin, destination, value, setting, problem.

    if is_vessel(destination) {
        problem(20, "'final_orbit_type' is not applicable to Vessel").
    }
    else if value = "none" {
        setting(rsvp:no_insertion_deltav).
    }
    else if value = "circular" {
        settings(rsvp:circular_insertion_deltav).
    }
    else if value = "elliptical" {
        setting(rsvp:elliptical_insertion_deltav).
    }
    else {
        problem(21, "'final_orbit_type' is not one of expected values 'none', 'circular' or 'elliptical'").
    }    
}

local function validate_final_orbit_pe {
    parameter origin, destination, value, setting, problem.

    if is_vessel(destination) {
        problem(22, "'final_orbit_pe' is not applicable to Vessel").
    }
    else if is_scalar(value) {
        if setting(value) < 0 {
            problem(23, "'final_orbit_pe' must be greater than or equal to zero").
        }            
    }
    else if value = "min" {
        local altitude is choose destination:atm:height + 10000 if destination:atm:exists else 10000.
        setting(altitude).
    }
    else {
        problem(24, "'final_orbit_pe' is not expected type Scalar or special value 'min'").
    }
}

local function validate_create_maneuver_nodes {
    parameter origin, destination, value, setting, problem.

    if value = "none" {
        setting(value).
    }
    else if value = "first" or value = "both" {
        setting(value).
        if hasnode {
            problem(25, "Existing maneuver node already exists").
        }
        if is_body(origin) {
            problem(26, "Can't add maneuver node to origin " + origin:name).
        }        
    }
    else {
        problem(27, "'create_maneuver_nodes' is not one of expected values 'none', 'first' or 'both'").
    }
}

local function validate_verbose {
   parameter origin, destination, value, setting, problem.

    if is_boolean(value) {
        setting(value).
    }
    else {
        problem(28, "'verbose' is not expected type Boolean").
    }    
}

local function default_earliest_departure {
    parameter origin, destination.

    return time():seconds + 120.
}

local function default_search_duration {
    parameter origin, destination.

    return max(rsvp:max_period(origin, destination), rsvp:synodic_period(origin, destination)).
}

local function default_max_time_of_flight {
    parameter origin, destination.

    return rsvp:ideal_hohmann_transfer_period(origin, destination).
}

local function default_initial_orbit_type {
    parameter origin, destination.

    return choose rsvp:equatorial_ejection_deltav if is_body(origin) else rsvp:vessel_ejection_deltav.
}

local function default_initial_orbit_pe {
    parameter origin, destination.

    return 100000.
}

local function default_final_orbit_type {
    parameter origin, destination.

    return choose rsvp:circular_insertion_deltav if is_body(destination) else rsvp:vessel_insertion_deltav.
}

local function default_final_orbit_pe {
    parameter origin, destination.

    return 100000.
}

local function default_create_maneuver_nodes {
    parameter origin, destination.

    return "none".
}

local function default_verbose {
    parameter origin, destination.

    return false.
}

local function success {
    parameter settings.

    return lexicon("success", true, "settings", settings).
}

local function failure {
    parameter problems.

    return lexicon("success", false, "problems", problems).
}

local function is_type {
    parameter typename, structure.

    return typename = structure:typename.
}