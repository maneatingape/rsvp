@lazyglobal off.

// Override this parameter to use the library from a different path or volume.
parameter base_path is "0:/rsvp".

// Functions are added to this lexicon by the "export" method
// to prevent pollution of the global namespace.
global rsvp is lexicon().

import("lambert.ks").
import("maneuver.ks").
import("orbit.ks").
import("search.ks").
import("transfer.ks").
import("validate.ks").

local function import {
    parameter filename.

    runoncepath(base_path + "/" + filename, export@).
}

local function export {
    parameter key, value.

    rsvp:add(key, value).
}