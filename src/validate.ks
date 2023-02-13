@lazyglobal off.

parameter export.
export("validate_parameters", validate_parameters@).

// Default value and validation function for each possible option key.
local delegates is lex(
    "verbose", list(false, validate_boolean(1)),
    "create_maneuver_nodes", list("none", validate_list(2, list("none", "first", "both"))),
    "earliest_departure", list("default", validate_scalar(3)),
    "search_duration", list("default", validate_scalar(4)),
    "search_interval", list("default", validate_scalar(5)),
    "max_time_of_flight", list("default", validate_scalar(6)),
    "final_orbit_periapsis", list(100000, validate_scalar(7)),
    "final_orbit_type", list("circular", validate_list(8, list("circular", "elliptical", "none"))),
    "final_orbit_orientation", list("prograde", validate_list(9, list("prograde", "polar", "retrograde"))),
    "cleanup_maneuver_nodes", list(true, validate_boolean(10))
).

// Collect valid options into "settings" and error messages into "problems".
local function validate_parameters {
    parameter destination, options.

    local settings is lex().
    local problems is lex().

    function setting {
        parameter key, value.
        settings:add(key, value).
    }

    function problem {
        parameter key, value.
        problems:add(key, value).
    }

    validate_prerequisites(problem@).
    validate_orbital_constraints(destination, setting@, problem@).
    validate_options(destination, options, setting@, problem@).

    if problems:length = 0 {
        return lex("success", true, "settings", settings).
    }
    else {
        return lex("success", false, "problems", problems).
    }
}

// Basic sanity checks.
local function validate_prerequisites {
    parameter problem.

    if ship <> kuniverse:activevessel {
        problem(101, "Ship '" + ship:name + "'' is not active vessel").
    }
    else if hasnode {
        problem(102, "Existing maneuver node already exists").
    }

    if not career():canmakenodes {
        problem(104, "Career mode has not unlocked maneuver nodes").
    }
    if career():patchlimit = 0 {
        problem(105, "Career mode has not unlocked patched conics").
    }
}

// Sanity check destination type and relation to vessel.
local function validate_orbital_constraints {
    parameter destination, setting, problem.

    if destination:istype("vessel") {
        setting("destination_type", "vessel").
    }
    else if destination:istype("body") {
        setting("destination_type", "body").
    }
    else {
        problem(201, "Parameter 'destination' is not expected type Orbitable (Vessels and Bodies)").
        return.
    }

    if not destination:hasbody {
        problem(202, "Destination '" + destination:name + "' is not orbiting a parent body").
        return.
    }

    if destination = ship {
        problem(203, "Origin and destination must be different").
    }
    if destination = ship:body {
        problem(204, "Ship '" + ship:name + "' is already in orbit around destination").
    }

    if ship:body = destination:body {
        setting("origin_type", "vessel").
    }
    else if ship:body:hasbody and ship:body:body = destination:body {
        setting("origin_type", "body").
    }
    else {
        problem(205, "Destination '" + destination:name + "' is not orbiting a direct common parent or grandparent of ship '" + ship:name + "'").
    }
}

local function validate_options {
    parameter destination, options, setting, problem.

    if not options:istype("lexicon") {
        problem(301, "Parameter 'options' is not expected type Lexicon").
        return.
    }

    // Check for keys that aren't valid when destination is a vessel.
    if destination:istype("vessel") {
        local not_applicable is list("periapsis", "type", "orientation").
        local found is list().

        for suffix in not_applicable {
            local key is "final_orbit_" + suffix.
            if options:haskey(key) {
                found:add(key).
            }
        }

        if found:length > 0 {
            problem(302, "Option " + to_string(found) + " not applicable to Vessel").
        }
    }

    // Check that final orbit periapsis is within destination SOI
    if destination:istype("body") {
        local key is "final_orbit_periapsis".
        local limit is floor(destination:soiradius - destination:radius).

        if options:haskey(key) and options[key] >= limit {
            problem(304, "Option '" + key + "'' must be less than " + limit).
        }
    }

    // Manuever nodes can only be created when the ship is in a stable orbit
    if ship:status <> "orbiting" {
        local key is "create_maneuver_nodes".

        if options:haskey(key) and options[key] <> "none" {
            problem(305, "Cannot create manuever nodes when ship '" + ship:name + "' is not in stable orbit").
        }
    }    

    // Check for unknown keys that indicate a typo.
    local found is list().

    for key in options:keys {
        if not delegates:haskey(key) {
            found:add(key).
        }
    }

    if found:length > 0 {
        problem(303, "Option " + to_string(found) + " not recognised").
    }

    // For each setting use either provided option or sensible default.
    for key in delegates:keys {
        local default_value is delegates[key][0].
        local validate_option is delegates[key][1].

        if options:haskey(key) {
            validate_option(key, options[key], setting, problem).
        }
        else {
            setting(key, default_value).
        }
    }
}

local function validate_boolean {
    parameter code.

    return {
        parameter key, value, setting, problem.

        if value:istype("boolean") {
            setting(key, value).
        }
        else {
            problem(code, "Option '" + key + "' is '" + value + "', expected boolean").
        }
    }.
}

local function validate_scalar {
    parameter code.

    return {
        parameter key, value, setting, problem.

        if value:istype("scalar") and value > 0 {
            setting(key, value).
        }
        else {
            problem(code, "Option '" + key + "' is '" + value + "', expected positive number").
        }
    }.
}

local function validate_list {
    parameter code, items.

    return {
        parameter key, value, setting, problem.

        if items:contains(value) {
            setting(key, value).
        }
        else {
            problem(code, "Option '" + key + "' is '" + value + "', expected one of " + to_string(items)).
        }
    }.
}

local function to_string {
    parameter items.

    return "'" + items:join("', '") + "'".
}