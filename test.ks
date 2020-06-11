@lazyglobal off.
runoncepath("kos-launch-window-finder/main.ks").

// Default value is 250, increase speed 8x as finding the lowest delta-v
// transfer is computationally intensive.
set config:ipu to 2000.

print find_launch_window(kerbin, duna).
//print find_launch_window(kerbin, moho).
//print find_launch_window(kerbin, eeloo).
//print find_launch_window(laythe, tylo).