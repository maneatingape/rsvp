@lazyglobal off.

global function iterated_hill_climb {
    parameter total_deltav, departure_time, search_duration, max_time_of_flight, step.

    local start is departure_time.
    local end is start + search_duration.

    for offset in range(start, end, step) {
        print "-------".
        print "Starting Offset: " + secondsToKerbinTime(offset).
        hill_climb(offset, step * 0.1, max_time_of_flight, total_deltav).
    }
}

local function hill_climb {
    parameter base_offset, stepSize, max_time_of_flight, total_deltav.

    local threshold is 3600.
    local offsetX is stepSize + base_offset.
    local offsetY is max_time_of_flight / 2.

    local prograde_deltav is total_deltav(false, offsetX, offsetX + offsetY).
    local retrograde_deltav is total_deltav(true, offsetX, offsetX + offsetY).
    local flip_direction is retrograde_deltav < prograde_deltav.

    local count is 0.
    local cost is {
        parameter offsetX, offsetY.

        return total_deltav(flip_direction, offsetX, offsetX + offsetY).
    }.

    local current is choose retrograde_deltav if flip_direction else prograde_deltav.
    local dx is 0.
    local dy is 0.
    local minX is 0.
    local minY is 0.

    until stepSize < threshold {
        local nextX is max(offsetX + dx, threshold).
        local nextY is max(offsetY + dy, threshold).

        if dx <> 0 {
            set minX to cost(nextX, offsetY).
        }
        else {
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
        }
        else {
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
        }
        else if minX < minY {
            set current to minX.
            set offsetX to nextX.
        }
        else {
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