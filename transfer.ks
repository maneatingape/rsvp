runoncepath("kos-launch-window-finder/lambert.ks").

// Default is 250, increase speed 8x
set config:ipu to 2000.

iterated_gradient_descent(sun, kerbin, duna).
//iterated_gradient_descent(sun, kerbin, moho).
//iterated_gradient_descent(sun, kerbin, eeloo).
//iterated_gradient_descent(jool, laythe, tylo).
//iterated_gradient_descent(sun, kerbin, jool).

print_stats().

global function iterated_gradient_descent {
    parameter focalBody, fromBody, toBody.

    local from_period is fromBody:orbit:period.
    local to_period is toBody:orbit:period.
    local synodic_period is abs(from_period * to_period / (from_period - to_period)).

    local start is 0.
    local end is max(max(from_period, to_period), synodic_period).
    local step is min(from_period, to_period).

    for offset in range(start, end, step) {
        gradient_descent(focalBody, fromBody, toBody, offset, step * 0.1).
    }
}

local function gradient_descent {
    parameter focalBody, fromBody, toBody, baseOffset, stepSize.

    local threshold is 3600.

    local offsetX is stepSize + baseOffset.
    local offsetY is tofInitialGuess(focalBody, fromBody, toBody).

    local progradeDeltaV is totalDeltaV(focalBody, fromBody, toBody, false, offsetX, offsetX + offsetY).
    local retrogradeDeltaV is totalDeltaV(focalBody, fromBody, toBody, true, offsetX, offsetX + offsetY).
    local flipDirection is retrogradeDeltaV < progradeDeltaV.

    local count is 0.
    local cost is {
        parameter offsetX, offsetY.

        set count to count + 1.
        return totalDeltaV(focalBody, fromBody, toBody, flipDirection, 0 + offsetX, 0 + offsetX + offsetY).
    }.

    local current is choose retrogradeDeltaV if flipDirection else progradeDeltaV.
    local dx is 0.
    local dy is 0.
    local minX is 0.
    local minY is 0.

    until stepSize < threshold {
        local nextX is max(offsetX + dx, threshold).
        local nextY is max(offsetY + dy, threshold).

        if dx <> 0 {
            set minX to cost(nextX, offsetY).
        } else {
            local east is cost(offsetX + stepSize, offsetY).
            local west is cost(max(offsetX - stepSize, threshold), offsetY).

            if east < west {
                set minX to east.
                set dx to stepSize.
            } else {
                set minX to west.
                set dx to -stepSize.
            }

            set nextX to max(offsetX + dx, threshold).
        }

        if dy <> 0 {
            set minY to cost(offsetX, nextY).
        } else {
            local north is cost(offsetX, offsetY + stepSize).
            local south is cost(offsetX, max(offsetY - stepSize, threshold)).

            if north < south {
                set minY to north.
                set dy to stepSize.
            } else {
                set minY to south.
                set dy to -stepSize.
            }

            set nextY to max(offsetY + dy, threshold).
        }

        if current < minX and current < minY {
            set dx to 0.
            set dy to 0.
            set stepSize to stepSize / 2.
        } else if minX < minY {
            set current to minX.
            set offsetX to nextX.
        } else {
            set current to minY.
            set offsetY to nextY.
        }
    }

    print "-------".
    print count.
    print round(current).
    print secondsToKerbinTime(0 + offsetX).
    print secondsToKerbinTime(0 + offsetX + offsetY).
}

local function tofInitialGuess {
    parameter focalBody, fromBody, toBody.

    // Return the time of half a Hohmann transfer between the two bodies
    local a is (fromBody:orbit:semimajoraxis + toBody:orbit:semimajoraxis) / 2.
    return constant:pi * sqrt(a ^ 3 / focalBody:mu).
}

local function totalDeltaV {
    parameter focalBody, fromBody, toBody, flip_direction, t1, t2.

    local solution is transferDeltaV(focalBody, fromBody, t1, toBody, t2, flip_direction).
    local ejection is ejectionDeltaV(fromBody, 100000, solution:dv1).
    local insertion is insertionDeltaV(toBody, 100000, solution:dv2).

    return ejection + insertion.
}

local function transferDeltaV {
    parameter focalBody, fromBody, t1, toBody, t2, flip_direction.

    local r1 is positionat(fromBody, t1) - focalBody:position.
    local r2 is positionat(toBody, t2) - focalBody:position.
    local solution is lambert(r1, r2, t2 - t1, focalBody:mu, flip_direction).

    local dv1 is solution:v1 - velocityat(fromBody, t1):orbit.
    local dv2 is solution:v2 - velocityat(toBody, t2):orbit.
    return lexicon("dv1", dv1, "dv2", dv2).
}

local function ejectionDeltaV {
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

local function insertionDeltaV {
    parameter body, altitude, dv2.

    local r1 is body:radius + altitude.
    local r2 is body:soiradius.

    local mu is body:mu.
    local v1 is sqrt(mu / r1).
    local v2 is dv2:mag.

    return sqrt(v2 ^ 2 - 2 * mu * (r1 - r2) / (r1 * r2)) - v1.
}

local function secondsToKerbinTime {
    parameter seconds.

    local timespan is time(seconds).
    return timespan:calendar + " " + timespan:clock.
}