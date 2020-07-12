@lazyglobal off.

parameter export.
export("find_transfer", find_transfer@).
export("line_search", line_search@).
// TODO: Get rid of this?
export("get_insertion_deltav_function", get_insertion_deltav_function@).

local one_dimension is list(v(1, 0, 0), v(-1, 0, 0)).
local two_dimensions is list(v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0)).

local function find_transfer {
    parameter destination, settings.

    local origin is choose ship if settings:origin_is_vessel else ship:body.

    local verbose is settings:verbose.

    local earliest_departure is settings:earliest_departure.
    if earliest_departure = "default" {
        set earliest_departure to time():seconds + 120.
    }

    local search_duration is settings:search_duration.
    if search_duration = "default" {
        local max_period is rsvp:max_period(origin, destination).
        local synodic_period is rsvp:synodic_period(origin, destination).
        set search_duration to max(max_period, synodic_period).
    }

    local max_time_of_flight is settings:max_time_of_flight.
    if max_time_of_flight = "default" {
        set max_time_of_flight to rsvp:ideal_hohmann_transfer_period(origin, destination).
    }

    local min_period is rsvp:min_period(origin, destination).
    local search_interval is 0.5 * min_period.
    local search_threshold is max(120, min(0.001 * min_period, 3600)).

    local transfer_deltav is rsvp:transfer_deltav:bind(origin, destination).
    local ejection_deltav is choose rsvp:vessel_ejection_deltav if settings:origin_is_vessel else rsvp:equatorial_ejection_deltav.
    local insertion_deltav is choose rsvp:vessel_insertion_deltav if settings:destination_is_vessel else get_insertion_deltav_function(settings).

    local initial_orbit_periapsis is max(ship:periapsis, 0).
    local final_orbit_periapsis is settings:final_orbit_periapsis.


    function transfer_details {
        parameter flip_direction, departure_time, arrival_time.

        local details is transfer_deltav(flip_direction, departure_time, arrival_time).
        local ejection is ejection_deltav(origin, initial_orbit_periapsis, details).
        local insertion is insertion_deltav(destination, final_orbit_periapsis, details:dv2).

        return lex("ejection", ejection, "insertion", insertion).
    }

    function transfer_cost {
        parameter flip_direction, departure_time, time_of_flight.

        local arrival_time is departure_time + time_of_flight.
        local details is transfer_details(flip_direction, departure_time, arrival_time).

        return details:ejection + details:insertion.
    }

    local transfer is iterated_local_search(verbose, earliest_departure, search_duration, max_time_of_flight, search_interval, search_threshold, transfer_cost@).
    local details is transfer_details(transfer:flip_direction, transfer:departure_time, transfer:arrival_time).

    // Construct nested result structure
    local departure is lex("time", transfer:departure_time, "deltav", details:ejection).
    local arrival is lex("time", transfer:arrival_time, "deltav", details:insertion).
    local predicted is lex("departure", departure, "arrival", arrival).
    // TODO: Can transfer be removed?
    local result to lex("success", true, "predicted", predicted, "transfer", transfer).

    return result.
}

local function get_insertion_deltav_function {
    parameter settings.

    local values is lex(
        "circular", rsvp:circular_insertion_deltav,
        "elliptical", rsvp:elliptical_insertion_deltav,
        "none", rsvp:no_insertion_deltav
    ).

    return values[settings:final_orbit_type].
}

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
local function iterated_local_search {
    parameter verbose, earliest_departure, search_duration, max_time_of_flight, search_interval, step_threshold, total_deltav.

    // The default max_time_of_flight is twice the ideal Hohmann transfer time,
    // so setting the intial guess to half of that will be reasonably close to
    // the final value in most cases.
    local y is max_time_of_flight * 0.5.
    local latest_departure is earliest_departure + search_duration.
    local step_size is search_interval * 0.1.

    // Sneaky trick here. When comparing a scalar and a string, kOS converts the
    // scalar to a string then compares them lexicographically.
    // This means that *any* number will always be less than the string "max"
    // as "m" is a higher codepoint than the numeric digits 0-9.
    local result is lex("total_deltav", "max").
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
        local candidate is grid_search(cost@, x, y, initial_deltav, step_size, step_threshold).
        local departure_time is candidate:position:x.
        local arrival_time is candidate:position:x + candidate:position:y.
        local total_deltav is candidate:minimum.

        if verbose {
            print "Search offset: " + seconds_to_kerbin_time(x).
            print "  Departure: " + seconds_to_kerbin_time(departure_time).
            print "  Arrival: " + seconds_to_kerbin_time(arrival_time).
            print "  Delta-v: " + round(total_deltav).
        }

        if total_deltav < result:total_deltav {
            set result to lex(
                "departure_time", departure_time,
                "arrival_time", arrival_time,
                "total_deltav", total_deltav,
                "flip_direction", flip_direction
            ).
        }
    }

    if verbose {
        print "Invocations: " + invocations.
        print "Best Result".
        print "  Departure: " + seconds_to_kerbin_time(result:departure_time).
        print "  Arrival: " + seconds_to_kerbin_time(result:arrival_time).
        print "  Delta-v: " + round(result:total_deltav).
    }

    return result.
}

// Convert epoch seconds to human readable string.
local function seconds_to_kerbin_time {
    parameter seconds.

    local timespan is time(seconds).

    return timespan:calendar + " " + timespan:clock.
}

// Convenience wrapper for searching a single dimension.
local function line_search {
    parameter cost, x, step_size, step_threshold.

    local position is v(x, 0, 0).
    local minimum is cost(position).

    return coordinate_descent(one_dimension, cost, position, minimum, step_size, step_threshold).
}

// Convenience wrapper for searching two dimensions.
local function grid_search {
    parameter cost, x, y, minimum, step_size, step_threshold.

    local position is v(x, y, 0).

    return coordinate_descent(two_dimensions, cost, position, minimum, step_size, step_threshold).
}

// Coordinate descent is a variant of the hill climbing algorithm, where only
// one dimension (x, y or z) is minimized at a time. This algorithm implements
// this with a simple binary search approach. This converges reasonable quickly
// wihout too many invocations of the "cost" function.
//
// The approach is:
// (1) Choose an initial starting position
// (2) Determine the lowest cost at a point "step_size" distance away, looking
//     in both positive and negative directions on the x, y and z axes.
// (3) Continue in this direction until the cost increases
// (4) Reduce the step size by half, terminating if below the threshold
//     then go to step (2)
local function coordinate_descent {
    parameter dimensions, cost, position, minimum, step_size, step_threshold.

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
            set step_size to step_size * 0.5.
        }
        else {
            set position to next_position.
        }
    }

    return lex("position", position, "minimum", minimum).
}