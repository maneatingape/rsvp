@lazyglobal off.

global function iterated_hill_climb {
    parameter earliest_departure, latest_departure, search_interval, max_time_of_flight, total_deltav, verbose.

    local clamp_y is clamp@:bind(0, max_time_of_flight).
    local y is max_time_of_flight * 0.5.

    local step_size is search_interval * 0.1.
    local step_threshold is 3600.
    local step_factor is 0.5.

    local invocations is 0.
    local result is lexicon("deltav", "max").

    for x in range(earliest_departure, latest_departure, search_interval) {
        local min_x is max(earliest_departure, x - search_interval).
        local max_x is min(latest_departure, x + 2 * search_interval).
        local clamp_x is clamp@:bind(min_x, max_x).

        local candidate is coordinate_descent(clamp_x, clamp_y, x, y, step_size, step_threshold, step_factor, total_deltav).
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

local function coordinate_descent {
    parameter clamp_x, clamp_y, x, y, step_size, step_threshold, step_factor, total_deltav.

    local prograde_deltav is total_deltav(false, x, y).
    local retrograde_deltav is total_deltav(true, x, y).    
    local flip_direction is retrograde_deltav < prograde_deltav.

    local deltav is choose retrograde_deltav if flip_direction else prograde_deltav.
    local invocations is 2.
    local direction is "none".

    local function cost {
        parameter next_x, next_y.
        
        if next_x = x and next_y = y {
            return deltav.
        }
        else {
            set invocations to invocations + 1.
            return total_deltav(flip_direction, next_x, next_y).
        }
    }

    until step_size < step_threshold {
        local north is deltav.
        local south is deltav.
        local east is deltav.
        local west is deltav.

        if direction = "north" or direction = "none" {
            set north to cost(x, clamp_y(y + step_size)).
        }
        if direction = "south" or direction = "none" {
            set south to cost(x, clamp_y(y - step_size)).
        }
        if direction = "east" or direction = "none" {
            set east to cost(clamp_x(x + step_size), y).
        }
        if direction = "west" or direction = "none" {
            set west to cost(clamp_x(x - step_size), y).
        }

        if north < deltav and north < south and north < east and north < west {
            set direction to "north".
            set deltav to north.
            set y to clamp_y(y + step_size).
        }
        else if south < deltav and south < east and south < west {
            set direction to "south".
            set deltav to south.
            set y to clamp_y(y - step_size).
        }
        else if east < deltav and east < west {
            set direction to "east".
            set deltav to east.
            set x to clamp_x(x + step_size).
        }
        else if west < deltav {
            set direction to "west".
            set deltav to west.
            set x to clamp_x(x - step_size).
        }
        else {
            set direction to "none".
            set step_size to step_size * step_factor.
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