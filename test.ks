@lazyglobal off.
runoncepath("kos-launch-window-finder/main.ks").

// Default value is 250, increase speed 8x as finding the lowest delta-v
// transfer is computationally intensive.
set config:ipu to 2000.

local options is lexicon("verbose", true).

find_launch_window(kerbin, duna, options).
//find_launch_window(kerbin, moho, options).
//find_launch_window(kerbin, eeloo, options).
//find_launch_window(laythe, tylo, options).
//find_launch_window(eeloo, moho, options).