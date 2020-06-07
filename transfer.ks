@lazyglobal off.
runoncepath("kos-launch-window-finder/orbit.ks").

// Default is 250, increase speed 8x
set config:ipu to 2000.

iterated_gradient_descent(sun, kerbin, duna).
//iterated_gradient_descent(sun, kerbin, moho).
//iterated_gradient_descent(sun, kerbin, eeloo).
//iterated_gradient_descent(jool, laythe, tylo).
//iterated_gradient_descent(sun, kerbin, jool).
//test().

local function test {
    local planets is list(jool, dres, duna, kerbin).

    for fromBody in planets {
        for toBody in planets {
            if fromBody <> toBody {
                iterated_gradient_descent(sun, fromBody, toBody).
            }
        }
    }
}

local function iterated_gradient_descent {
    parameter focalBody, fromBody, toBody.

    local from_period is fromBody:orbit:period.
    local to_period is toBody:orbit:period.
    local synodic_period is abs(from_period * to_period / (from_period - to_period)).

    local start is 0.
    local end is max(max(from_period, to_period), synodic_period).
    local step is min(from_period, to_period).

    for offset in range(start, end, step) {
        print "-------".        
        print fromBody:name + " => " + toBody:name.
        print "Starting Offset: " + secondsToKerbinTime(offset).
        gradient_descent(focalBody, fromBody, toBody, offset, step * 0.1).
    }
}

local function gradient_descent {
    parameter focalBody, fromBody, toBody, baseOffset, stepSize.

    local threshold is 3600.
    local offsetX is stepSize + baseOffset.
    local offsetY is tof_initial_guess(focalBody, fromBody, toBody).

    local progradeDeltaV is total_deltav(focalBody, fromBody, toBody, false, offsetX, offsetX + offsetY).
    local retrogradeDeltaV is total_deltav(focalBody, fromBody, toBody, true, offsetX, offsetX + offsetY).
    local flipDirection is retrogradeDeltaV < progradeDeltaV.

    local count is 0.
    local cost is {
        parameter offsetX, offsetY.

        return total_deltav(focalBody, fromBody, toBody, flipDirection, 0 + offsetX, 0 + offsetX + offsetY).
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

    print "Departure: " + secondsToKerbinTime(0 + offsetX).
    print "Arrival: " + secondsToKerbinTime(0 + offsetX + offsetY).
    print "Delta V: " + round(current).
}

local function secondsToKerbinTime {
    parameter seconds.

    local timespan is time(seconds).
    return timespan:calendar + " " + timespan:clock.
}