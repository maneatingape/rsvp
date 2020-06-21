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
    parameter earliest_departure, latest_departure, search_interval, step_threshold, max_time_of_flight, total_deltav, verbose.

    // The default max_time_of_flight is twice the ideal Hohmann transfer time,
    // so setting the intial guess to half of that will be reasonably close to
    // the final value in most cases.
    local y is max_time_of_flight * 0.5.
    local step_size is search_interval * 0.1.
    local step_factor is 0.5.

    // Sneaky trick here. When comparing a scalar and a string, kOS converts the
    // scalar to a string then compares them lexicographically.
    // This means that *any* number will always be less than the string "max"
    // as "m" is a higher codepoint than the numeric digits 0-9.
    local result is lexicon("total_deltav", "max").
    local invocations is 0.

    for x in range(earliest_departure, latest_departure, search_interval) {
        // Restrict x to a limited range of the total search space to save time.
        // If x wanders too far from its original value, then most likely the
        // prevous search has already found that minimum or the next search will
        // find it.
        local min_x is max(earliest_departure, x - search_interval).
        local max_x is min(latest_departure, x + 2 * search_interval).

        // Calculate the intial delta-v value at the starting point and also figure
        // out which direction we should be going.
        local prograde_deltav is total_deltav(false, x, y).
        local retrograde_deltav is total_deltav(true, x, y).
        local flip_direction is retrograde_deltav < prograde_deltav.
        local initial_deltav is choose retrograde_deltav if flip_direction else prograde_deltav.

        set invocations to invocations + 2.
        function cost {
            parameter v.

            // y is always bounded to the interval [0, max_time_of_flight]
            if v:x < min_x or v:x > max_x or v:y < 0 or v:y > max_time_of_flight {
                return "max".
            }
            else {
                set invocations to invocations + 1.
                return total_deltav(flip_direction, v:x, v:y).
            }
        }

        // Start a search from this location, updating "result" if "candidate" delta-v is lower.
        local candidate is coordinate_descent_2d(cost@, v(x, y, 0), initial_deltav, step_size, step_threshold, step_factor).
        local departure is candidate:position:x.
        local arrival is candidate:position:x + candidate:position:y.
        local deltav is candidate:minimum.

        if verbose {
            print "Search offset: " + seconds_to_kerbin_time(x).
            print "  Departure: " + seconds_to_kerbin_time(departure).
            print "  Arrival: " + seconds_to_kerbin_time(arrival).
            print "  Delta-v: " + round(deltav).
        }

        if deltav < result:total_deltav {
            set result to lexicon().
            result:add("departure", departure).
            result:add("arrival", arrival).
            result:add("total_deltav", deltav).
            result:add("flip_direction", flip_direction).
        }
    }

    if verbose {
        print "Invocations: " + invocations.
        print "Best Result".
        print "  Departure: " + seconds_to_kerbin_time(result:departure).
        print "  Arrival: " + seconds_to_kerbin_time(result:arrival).
        print "  Delta-v: " + round(result:total_deltav).
    }

    return result.
}

global function refine_maneuver_node {
    parameter intercept_distance, position.

    local invocations is 0.
    local initial_cost is cost(position).

    local step_size is 1.
    local step_threshold is 0.001.
    local step_factor is 0.9.

    local function cost {
        parameter v.
        set invocations to invocations + 1.
        return intercept_distance(v).
    }

    return coordinate_descent_3d(cost@, position, initial_cost, step_size, step_threshold, step_factor).
}

// Coordinate descent is a variant of the hill climbing algorithm, where only
// one dimension (x or y) is minimized at a time. This algorithm implements this
// with a simple binary search approach. This converges reasonable quickly wihout
// too many costly Lambert solver invocations.
//
// The approach is:
// (1) Choose an initial starting position
// (2) Determine the lowest cost at a point "step_size" distance away, looking
//     in both positive and negative directions on the x, y and z axes.
// (3) Continue in this direction until the cost increases
// (4) Half the step size, terminating if below the threshold, then go to step (2)
local function coordinate_descent {
    parameter dimensions, cost, position, minimum, step_size, step_threshold, step_factor.

    local next_position is position.
    local direction is "none".

    local function test {
        parameter test_direction.

        local test_position is position + step_size * test_direction.
        local test_cost is cost(test_position).

        if test_cost < minimum {
            set minimum to test_cost.
            set next_position to test_position.
            set direction to test_direction.
        }
        // Stop if we are currently line searching.
        else if direction = test_direction {
            set direction to "none".
        }
    }

    until step_size < step_threshold {
        if direction = "none" {
            for test_direction in dimensions {
                test(test_direction).
            }
        }
        else {
            test(direction).
        }

        if direction = "none" {
            set step_size to step_size * step_factor.
        }
        else {
            set position to next_position.
        }
    }

    return lexicon("position", position, "minimum", minimum).
}

local one_dimension is list(v(1, 0, 0), v(-1, 0, 0)).
local two_dimensions is list(v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0)).
local three_dimensions is list(v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0), v(0, 0, 1), v(0, 0, -1)).

global coordinate_descent_1d is coordinate_descent@:bind(one_dimension).
global coordinate_descent_2d is coordinate_descent@:bind(two_dimensions).
global coordinate_descent_3d is coordinate_descent@:bind(three_dimensions).

global function seconds_to_kerbin_time {
    parameter seconds.

    local timespan is time(seconds).

    return timespan:calendar + " " + timespan:clock.
}