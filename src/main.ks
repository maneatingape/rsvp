@lazyglobal off.

// Local functions are added to this lexicon by the "export" method
// in order to make them available to other scripts
// while preventing pollution of the global namespace.
global rsvp is lex().

import("lambert.ks").
import("maneuver.ks").
import("orbit.ks").
import("search.ks").
import("transfer.ks").
import("validate.ks").

local function import {
    parameter filename.

    local full_path is scriptpath():parent:combine(filename).
    runoncepath(full_path, export@).
}

local function export {
    parameter key, value.

    rsvp:add(key, value).
}