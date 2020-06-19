@lazyglobal off.
runoncepath("0:/rsvp/main.ks").

// Default value is 250. Overclocking CPU speed to maximum is recommended
// as finding transfers is computationally intensive.
set config:ipu to 2000.

local options is lexicon("verbose", true).

// Planets outward journey
//find_launch_window(kerbin, moho, options).
//find_launch_window(kerbin, eve, options).
find_launch_window(kerbin, duna, options).
//find_launch_window(kerbin, jool, options).
//find_launch_window(kerbin, eeloo, options).

// Moons
//find_launch_window(laythe, tylo, options).

// Return journey
//find_launch_window(eeloo, moho, options).

//vessel_rendezvous().

local function vessel_rendezvous {
    until not hasnode {
        remove nextnode.
        wait 0.
    }

    local origin is vessel("Origin").
    local destination is vessel("Destination").
    print create_maneuver_nodes(origin, destination, options).
}