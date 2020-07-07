@lazyglobal off.

parameter export.
export("validate_parameters", validate_parameters@).

local delegates is lexicon(
    "verbose", list(false, validate_boolean@),
    "earliest_departure", list("default", validate_scalar@),
    "search_duration", list("default", validate_scalar@),
    "max_time_of_flight", list("default", validate_scalar@),
    "final_orbit_periapsis", list(100000, validate_scalar@),
    "final_orbit_type", list("circular", validate_list(list("circular", "elliptical", "none"))),
    "final_orbit_orientation", list("prograde", validate_list(list("prograde", "polar", "retrograde"))),
    "create_maneuver_nodes", list("none", validate_list(list("none", "first", "both")))
).

// Collect valid options into "settings" and error messages into "problems".
local function validate_parameters {
    parameter destination, options.

    local settings is lexicon().
    local problems is list().

    function problem {
        parameter value.
        problems:add(value).
    }

    validate_prerequisites(problem@).
    validate_orbital_constraints(destination, settings, problem@).
    validate_options(destination, options, settings, problem@).

    local success is problems:length = 0.
    local value is choose settings if success else problems.

    return lexicon("success", success, "value", value).
}

// Basic sanity checks
local function validate_prerequisites {
    parameter problem.

    if ship <> kuniverse:activevessel {
        problem("Can't add maneuver node as CPU vessel '" + ship:name + "'' is not active vessel").
    }
    else if hasnode {
        problem("Existing maneuver node already exists").
    }
    if ship:status <> "orbiting" {
        problem("Can't add maneuver node to ship not in stable orbit").
    }

    if not career():canmakenodes {
        problem("Career mode has not yet unlocked maneuver nodes").
    }
    if career():patchlimit = 0 {
        problem("Career mode has not yet unlocked patched conics").
    }
}

// Sanity check destination type and relation to vessel
local function validate_orbital_constraints {
    parameter destination, settings, problem.

    if not destination:istype("orbitable") {
        problem("Parameter 'destination' is not expected type Orbitable (Vessels and Bodies)").
        return.
    }
    if not destination:hasbody {
        problem( "Destination '" + origin:name + "' is not orbiting a parent body.").
        return.
    }

    if destination = ship {
        problem("'origin' and 'destination' must be different").
    }

    if ship:body = destination:body {        
        settings:add("origin_is_body", false).
    }
    else if ship:body:hasbody and ship:body:body = destination:body {
        settings:add("origin_is_body", true).
    }
    else {
        problem("Destination '" + destination:name + "' is not orbiting a direct common parent or grandparent of ship").
    }
}

// Check for keys that aren't valid when destination is a vessel
// or unknown keys that could indicate a typo, then for each setting
// use either provided option or sensible default
local function validate_options {
    parameter destination, options, settings, problem.

    if not options:istype("lexicon") {
        problem("Parameter 'options' is not expected type Lexicon").
        return.
    }

    if destination:istype("vessel") {
        for key in list("final_orbit_periapsis", "final_orbit_type", "final_orbit_orientation") {
            if options:haskey(key) {
                problem("'" + key + "' is not applicable to Vessel").
            }
        }
    }

    for key in options:keys {
        if not delegates:haskey(key) {
            problem("Option '" + key + "' is not recognised").
        }
    }

    for key in delegates:keys {
        local default_value is delegates[key][0].
        local validate_option is delegates[key][1].

        if options:haskey(key) {
            validate_option(key, options[key], settings, problem@).
        }
        else {
            settings:add(key, default_value).
        }
    }
}

local function validate_boolean {
    parameter key, value, settings, problem.

    if value:istype("boolean") {
        settings:add(key, value).
    }
    else {
        problems("'" + key + "'' is not a boolean, value is " + value).
    }
}

local function validate_scalar {
    parameter key, value, settings, problem.

    if value:istype("scalar") and value > 0 {
        settings:add(key, value).
    }
    else {
        problems("'" + key + "'' is not a positive number, value is " + value).
    }
}

local function validate_list {
    parameter items.

    return {
        parameter key, value, settings, problem.

        if items:contains(value) {
            settings:add(key, value).
        }
        else {
            problem("'" + key + "' is not one of values '" + list:join("', '") + "'").
        }
    }.
}