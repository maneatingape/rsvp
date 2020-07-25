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

    // Thoroughly check supplied parameters, options and game state for
    // correctness. If any problems are found, print validation details
    // to the console then exit early.
    local maybe is rsvp:validate_parameters(destination, options).

    if not maybe:success {
        print maybe.
        return maybe.
    }

    // Find the lowest deltav cost transfer using the specified settings.
    local settings is maybe:settings.
    local tuple is rsvp:find_launch_window(destination, settings).
    local transfer is tuple:transfer.
    local result is tuple:result.

    // If no node creation has been requested return predicted transfer details,
    // otherwise choose betwen the 4 combinations of possible transfer types.
    if settings:create_maneuver_nodes <> "none" {
        // Both "origin_type" and "destination_type" are either the string
        // "vessel" or "body", so can be used to construct the function
        // names for transfer, for example "vessel_to_vessel" or "body_to_body".
        local key is settings:origin_type + "_to_" + settings:destination_type.
        set result to rsvp[key](destination, settings, transfer, result).

        // In the case of failure delete any manuever nodes created.
        if not result:success and settings:cleanup_maneuver_nodes {
            for maneuver in allnodes {
                remove maneuver.
            }
        }
    }

    return result.
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