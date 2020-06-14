@lazyglobal off.
runoncepath("kos-launch-window-finder/main.ks").

// Default value is 250, increase speed 8x as finding the lowest delta-v
// transfer is computationally intensive.
set config:ipu to 2000.

local options is lexicon("verbose", true).

// Planets outward journey
//find_launch_window(kerbin, moho, options).
//find_launch_window(kerbin, eve, options).
//find_launch_window(kerbin, duna, options).
//find_launch_window(kerbin, jool, options).
//find_launch_window(kerbin, eeloo, options).

// Moons
//find_launch_window(laythe, tylo, options).

// Return journey
//find_launch_window(eeloo, moho, options).

vessel_rendezvous().

local function vessel_rendezvous {
	local origin is vessel("Origin").
	local destination is vessel("Destination").
	add create_maneuver_node(origin, destination, options):manuever.
}