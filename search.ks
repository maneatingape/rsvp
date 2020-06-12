@lazyglobal off.

global function iterated_hill_climb {
    parameter earliest_departure, latest_departure, search_interval, max_time_of_flight, total_deltav, verbose.

    local clamp_y is clamp@:bind(0, max_time_of_flight).
    local y is max_time_of_flight * 0.5.

    local step_size is search_interval * 0.1.
    local step_threshold is 3600.

    local invocations is 0.
    local result is lexicon("deltav", "max").

    for x in range(earliest_departure, latest_departure, search_interval) {
        local min_x is max(earliest_departure, x - search_interval).
        local max_x is min(latest_departure, x + 2 * search_interval).
        local clamp_x is clamp@:bind(min_x, max_x).

        local candidate is hill_climb(clamp_x, clamp_y, x, y, step_size, step_threshold, total_deltav).
        set invocations to invocations + candidate:invocations.
        set result to choose candidate if candidate:deltav < result:deltav else result.

        if verbose {
            print "Search offset: " + seconds_to_kerbin_time(x).
            print "  Departure: " + seconds_to_kerbin_time(candidate:departure).
            print "  Arrival: " + seconds_to_kerbin_time(candidate:arrival).
            print "  Delta-v: " + round(candidate:deltav).
        }
    }

    if verbose {
        print "Invocations: " + invocations.
        print "Best Result".
        print "  Departure: " + seconds_to_kerbin_time(result:departure).
        print "  Arrival: " + seconds_to_kerbin_time(result:arrival).
        print "  Delta-v: " + round(result:deltav).
    }

    return result.
}

local function hill_climb {
    parameter clamp_x, clamp_y, x, y, step_size, step_threshold, total_deltav.

    local prograde_deltav is total_deltav(false, x, y).
    local retrograde_deltav is total_deltav(true, x, y).    
    local flip_direction is retrograde_deltav < prograde_deltav.
    local deltav is choose retrograde_deltav if flip_direction else prograde_deltav.
    local invocations is 0.

    local cost is {
        parameter next_x, next_y.
        
        if next_x = x and next_y = y {
            return deltav.
        }
        else {
            set invocations to invocations + 1.
            return total_deltav(flip_direction, next_x, next_y).
        }
    }.

    local dx is 0.
    local dy is 0.
    local next_x is 0.
    local next_y is 0.
    local cost_x is 0.
    local cost_y is 0.

    until step_size < step_threshold {
        if dx <> 0 {
            set next_x to clamp_x(x + dx).
            set next_y to clamp_y(y + dy).
            set cost_x to cost(next_x, y).
            set cost_y to cost(x, next_y).
        }
        else {
            local east is cost(clamp_x(x + step_size), y).
            local west is cost(clamp_x(x - step_size), y).
            local north is cost(x, clamp_y(y + step_size)).
            local south is cost(x, clamp_y(y - step_size)).

            if east < west {
                set cost_x to east.
                set dx to step_size.
            } else {
                set cost_x to west.
                set dx to -step_size.
            }

            if north < south {
                set cost_y to north.
                set dy to step_size.
            } else {
                set cost_y to south.
                set dy to -step_size.
            }

            set next_x to clamp_x(x + dx).
            set next_y to clamp_y(y + dy).
        }

        if deltav <= cost_x and deltav <= cost_y {
            set dx to 0.
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

    return lexicon("success", true, "departure", x, "arrival", x + y, "deltav", deltav, "invocations", invocations).
}

local function clamp {
    parameter min_n, max_n, n.

    return min(max(n, min_n), max_n).
}

global function seconds_to_kerbin_time {
    parameter seconds.

    local timespan is time(seconds).
    return timespan:calendar + " " + timespan:clock.
}