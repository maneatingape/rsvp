@lazyglobal off.

// Local functions are added to this lexicon by the "export" method
// in order to make them available to other scripts while preventing pollution
// of the global namespace.
global rsvp is lex().
export("goto", goto@).

// Add functions from all other scripts into lexicon.
import("lambert.ks").
import("maneuver.ks").
import("orbit.ks").
import("search.ks").
import("transfer.ks").
import("validate.ks").

local function goto {
    parameter destination, options is lex().

    // Thoroughly check supplied parameters, options and game state for correctness.
    // Prints any validation problems found to the console then exits early.
    local maybe is rsvp:validate_parameters(destination, options).

    if not maybe:success {
        print maybe:value.
        return maybe.
    }

    // Find the lowest deltav cost transfer with the given settings.
    local settings is maybe:value.
    local tuple is rsvp:find_launch_window(destination, settings).
    local transfer is tuple:transfer.
    local result is tuple:result.

    // If no node creation has been requested return predicted transfer details,
    // otherwise choose betwen the 4 combinations of possible transfer types.
    if settings:create_maneuver_nodes = "none" {
        return result.
    }
    else if settings:origin_is_vessel {
        if settings:destination_is_vessel {
            return rsvp:vessel_to_vessel(destination, settings, transfer, result).
        }
        else {
            return rsvp:vessel_to_body(destination, settings, transfer, result).
        }
    }
    else {
        if settings:destination_is_vessel {
            return rsvp:body_to_vessel(destination, settings, transfer, result).
        }
        else {
            return rsvp:body_to_body(destination, settings, transfer, result).
        }
    }
}

local function export {
    parameter key, value.

    rsvp:add(key, value).
}

local function import {
    parameter filename.

    local full_path is scriptpath():parent:combine(filename).
    runoncepath(full_path, export@).
}