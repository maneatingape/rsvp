@lazyglobal off.

global function iterated_hill_climb {
    parameter start_time, end_time, search_interval, max_time_of_flight, total_deltav.

    local y is max_time_of_flight * 0.5.
    local clamp_y is clamp@:bind(0, max_time_of_flight).

    local step_size is search_interval * 0.1.
    local step_threshold is 3600.

    local result is lexicon("deltav", "max").

    for x in range(start_time, end_time, search_interval) {
        print "-------".
        print "Starting Offset: " + secondsToKerbinTime(x).
        
        local min_x is max(start_time, x - search_interval).
        local max_x is min(end_time, x + 2 * search_interval).
        local clamp_x is clamp@:bind(min_x, max_x).

        local candidate is hill_climb(clamp_x, clamp_y, x, y, step_size, step_threshold, total_deltav).
        set result to choose candidate if candidate:deltav < result:deltav else result.
    }

    return result.
}

local function hill_climb {
    parameter clamp_x, clamp_y, x, y, step_size, step_threshold, total_deltav.

    local prograde_deltav is total_deltav(false, x, y).
    local retrograde_deltav is total_deltav(true, x, y).
    
    local flip_direction is retrograde_deltav < prograde_deltav.
    local cost is total_deltav@:bind(flip_direction).
    local deltav is choose retrograde_deltav if flip_direction else prograde_deltav.

    local count is 0.
    local dx is 0.
    local dy is 0.

    until step_size < step_threshold {
        local next_x is -1.
        local next_y is -1.
        local cost_x is -1.
        local cost_y is -1.

        set count to count + 1.

        if dx <> 0 {
            set next_x to clamp_x(x + dx).
            set cost_x to choose deltav if next_x = x else cost(next_x, y).
        }
        else {
            local east is cost(clamp_x(x + step_size), y).
            local west is cost(clamp_x(x - step_size), y).

            if east < west {
                set cost_x to east.
                set dx to step_size.
            } else {
                set cost_x to west.
                set dx to -step_size.
            }

            set next_x to clamp_x(x + dx).
        }

        if dy <> 0 {
            set next_y to clamp_y(y + dy).
            set cost_y to choose deltav if next_y = y else cost(x, next_y).
        }
        else {
            local north is cost(x, clamp_y(y + step_size)).
            local south is cost(x, clamp_y(y - step_size)).

            if north < south {
                set cost_y to north.
                set dy to step_size.
            } else {
                set cost_y to south.
                set dy to -step_size.
            }

            set next_y to clamp_y(y + dy).
        }

        if deltav <= cost_x and deltav <= cost_y {
            set dx to 0.
            set dy to 0.
            set step_size to step_size * 0.5.
        }
        else if cost_x < cost_y {
            set deltav to cost_x.
            set x to next_x.
        }
        else {
            set deltav to cost_y.
            set y to next_y.
        }
    }

    print "Count: " + count.
    print "Departure: " + secondsToKerbinTime(x).
    print "Arrival: " + secondsToKerbinTime(x + y).
    print "Delta V: " + round(deltav).

    return lexicon("success", true, "departure_time", x, "tof", y, "deltav", deltav).
}

local function clamp {
    parameter min_n, max_n, n.
    return min(max(n, min_n), max_n).
}

local function secondsToKerbinTime {
    parameter seconds.

    local timespan is time(seconds).
    return timespan:calendar + " " + timespan:clock.
}