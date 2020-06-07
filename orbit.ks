@lazyglobal off.
runoncepath("kos-launch-window-finder/lambert.ks").

// Return the time of half a Hohmann transfer between the two bodies
global function tof_initial_guess {
    parameter focalBody, fromBody, toBody.

    local a is (fromBody:orbit:semimajoraxis + toBody:orbit:semimajoraxis) / 2.
    return constant:pi * sqrt(a ^ 3 / focalBody:mu).
}

global function total_deltav {
    parameter focalBody, fromBody, toBody, flip_direction, t1, t2.

    local solution is transfer_deltav(focalBody, fromBody, t1, toBody, t2, flip_direction).
    local ejection is ejection_deltav(fromBody, 100000, solution:dv1).
    local insertion is insertion_deltav(toBody, 100000, solution:dv2).

    return ejection + insertion.
}

local function transfer_deltav {
    parameter focalBody, fromBody, t1, toBody, t2, flip_direction.

    // To determine the position of a planet at a specific time "t" relative to
    // its parent body, then you must subtract the *current* position of the
    // parent body, not the position of the parent body at time "t" as may be expected.
    local r1 is positionat(fromBody, t1) - focalBody:position.
    local r2 is positionat(toBody, t2) - focalBody:position.
    local solution is lambert(r1, r2, t2 - t1, focalBody:mu, flip_direction).

    // Velocity is always relative to the parent body, so no adjustment needed.
    local dv1 is solution:v1 - velocityat(fromBody, t1):orbit.
    local dv2 is solution:v2 - velocityat(toBody, t2):orbit.
    return lexicon("dv1", dv1, "dv2", dv2).
}

local function ejection_deltav {
    parameter body, altitude, dv1.

    local r1 is body:radius + altitude.
    local r2 is body:soiradius.

    local mu is body:mu.
    local v1 is sqrt(mu / r1).
    local v2 is dv1:mag.

    local theta is vang(dv1, v(dv1:x, 0, dv1:z)).
    local escapeV is sqrt(v2 ^ 2 - 2 * mu * (r1 - r2) / (r1 * r2)).

    return sqrt(escapeV ^ 2 + v1 ^ 2 - 2 * escapeV * v1 * cos(theta)).
}

local function insertion_deltav {
    parameter body, altitude, dv2.

    local r1 is body:radius + altitude.
    local r2 is body:soiradius.

    local mu is body:mu.
    local v1 is sqrt(mu / r1).
    local v2 is dv2:mag.

    return sqrt(v2 ^ 2 - 2 * mu * (r1 - r2) / (r1 * r2)) - v1.
}