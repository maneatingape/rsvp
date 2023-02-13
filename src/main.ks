@lazyglobal off.

// Local functions are added to this lexicon by the "export" method
// in order to make them available to other scripts while preventing pollution
// of the global namespace.
global rsvp is lex().

// List of all source files. Omit extenstion so that users can use
// compiled version if desired.
local source_files is list(
    "hill_climb",
    "lambert",
    "main",
    "maneuver",
    "orbit",
    "refine",
    "search",
    "transfer",
    "validate"
).

export("goto", goto@).
export("compile_to", compile_to@).
import().

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
    local craft_transfer is tuple:transfer.
    local result is tuple:result.

    // If no node creation has been requested return predicted transfer details,
    // otherwise choose betwen the 4 combinations of possible transfer types.
    if settings:create_maneuver_nodes <> "none" {
        // Both "origin_type" and "destination_type" are either the string
        // "vessel" or "body", so can be used to construct the function
        // names for transfer, for example "vessel_to_vessel" or "body_to_body".
        local key is settings:origin_type + "_to_" + settings:destination_type.
        set result to rsvp[key](destination, settings, craft_transfer, result).

        if not result:success {
            // Print details to the console
            if settings:verbose {
                print result.
            }

            // In the case of failure delete any manuever nodes created.
            if settings:cleanup_maneuver_nodes {
                for maneuver in allnodes {
                    remove maneuver.
                }
            }
        }
    }

    return result.
}

// Add delegate to the global "rsvp" lexicon.
local function export {
    parameter key, value.

    rsvp:add(key, value).
}

// Add functions from all other scripts into lexicon. User can use compiled
// versions of the source, trading off less storage space vs harder to debug
// error messages.
local function import {
    local source_root is scriptpath():parent.

    for filename in source_files {
        local source_path is source_root:combine(filename).

        runoncepath(source_path, export@).
    }
}

// Compiles source files and copies them to a new location. This is useful to
// save space on processor hard disks that have limited capacity.
// The trade-off is that error messages are less descriptive.
local function compile_to {
    parameter destination.

    local source_root is scriptpath():parent.
    local destination_root is path(destination).

    // Check that path exists and is a directory.
    if not exists(destination_root) {
        print destination_root + " does not exist".
        return.
    }
    if open(destination_root):isfile {
        print destination_root + " is a file. Should be a directory".
        return.
    }

    for filename in source_files {
        local source_path is source_root:combine(filename + ".ks").
        local destination_path is destination_root:combine(filename + ".ksm").

        print "Compiling " + source_path.
        compile source_path to destination_path.
    }

    print "Succesfully compiled " + source_files:length + " files to " + destination_root.
}