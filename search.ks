@lazyglobal off.

// Local search algorithms such as hill climbing, gradient descent or
// coordinate descent can easily get stuck in local minima.
//
// A simple way to work around this drawback is to start several searches at
// different coordinates. There is then a good chance that at least one of the
// searches will find the global minimum.
//
// Our solution space is the classic porkchop plot, where the x coordinate is
// departure time and the y coordinate is time of flight. The Lambert solver and
// orbital parameters provides the "cost" function of the delta-v requirement
// at any given (x,y) point.
global function iterated_local_search {
    parameter earliest_departure, latest_departure, search_interval, threshold, max_time_of_flight, total_deltav, verbose.

    // y is always bounded to the interval [0, max_time_of_flight]
    local clamp_y is clamp@:bind(0, max_time_of_flight).
    // The default max_time_of_flight is twice the ideal Hohmann transfer time,
    // so setting the intial guess to half of that will be reasonably close to
    // the final value in most cases.
    local y is max_time_of_flight * 0.5.

    local step_size is search_interval * 0.1.
    local step_threshold is threshold.
    local step_factor is 0.5.

    // Sneaky trick here. When comparing a scalar and a string, kOS converts the
    // scalar to a string then compares them lexicographically.
    // This means that *any* number will always be less than the string "max"
    // as "m" is a higher codepoint than the numeric digits 0-9.
    local result is lexicon("deltav", "max").
    local invocations is 0.

    for x in range(earliest_departure, latest_departure, search_interval) {
        // Restrict x to a limited range of the total search space to save time.
        // If x wanders too far from its original value, then most likely the
        // prevous search has already found that minimum or the next search will
        // find it.
        local min_x is max(earliest_departure, x - search_interval).
        local max_x is min(latest_departure, x + 2 * search_interval).
        local clamp_x is clamp@:bind(min_x, max_x).

        // Start a search from this location, updating "result" if "candidate"
        // delta-v is lower.
        local candidate is coordinate_descent(clamp_x, clamp_y, x, y, step_size, step_threshold, step_factor, total_deltav).
        set result to choose candidate if candidate:deltav < result:deltav else result.
        set invocations to invocations + candidate:invocations.

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

// Coordinate descent is a variant of the hill climbing algorithm, where only
// one dimension (x or y) is minimized at a time. This algorithm implements this
// with a simple binary search approach. This converges reasonable quickly wihout
// too many costly Lambert solver invocations.
//
// The approach is:
// (1) Choose an initial starting position
// (2) Determine the lowest cost at a point "step_size" distance away, looking
//     in both directions on both the x and y axes.
// (3) Continue in this direction until the cost increases
// (4) Half the step size, terminating if below a threshold, then go to step (2)
local function coordinate_descent {
    parameter clamp_x, clamp_y, x, y, step_size, step_threshold, step_factor, total_deltav.

    // Calculate the intial delta-v value at the starting point and also figure
    // out which direction we should be going.
    local prograde_deltav is total_deltav(false, x, y).
    local retrograde_deltav is total_deltav(true, x, y).
    local flip_direction is retrograde_deltav < prograde_deltav.

    local deltav is choose retrograde_deltav if flip_direction else prograde_deltav.
    local invocations is 2.
    local direction is "none".

    // Tests the delta-v value in a particular direction, possibly updating
    // both delta-v and direction.
    local function cost {
        parameter dx, dy, next_direction is direction.

        local next_x is clamp_x(x + dx).
        local next_y is clamp_y(y + dy).
        local next_deltav is deltav.

        if next_x <> x or next_y <> y {
            set invocations to invocations + 1.
            set next_deltav to total_deltav(flip_direction, next_x, next_y).
        }

        if next_deltav < deltav {
            set deltav to next_deltav.
            set direction to next_direction.
        }
        else if direction = next_direction {
            set direction to "none".
        }
    }

    until step_size < step_threshold {
        if direction = "north" {
            cost(0, step_size).
        }
        else if direction = "south" {
            cost(0, -step_size).
        }
        else if direction = "east" {
            cost(step_size, 0).
        }
        else if direction = "west" {
            cost(-step_size, 0).
        }
        else {
            cost(0, step_size, "north").
            cost(0, -step_size, "south").
            cost(step_size, 0, "east").
            cost(-step_size, 0, "west").
        }

        if direction = "north" {
            set y to clamp_y(y + step_size).
        }
        else if direction = "south" {
            set y to clamp_y(y - step_size).
        }
        else if direction = "east" {
            set x to clamp_x(x + step_size).
        }
        else if direction = "west" {
            set x to clamp_x(x - step_size).
        }
        else {
            set step_size to step_size * step_factor.
        }
    }

    return lexicon("flip_direction", flip_direction, "departure", x, "arrival", x + y, "deltav", deltav, "invocations", invocations).
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