@lazyglobal off.

parameter export.
export("find_launch_window", find_launch_window@).

local function find_launch_window {
    parameter destination, settings.

    // For vessel-to-vessel or vessel-to-body transfers the origin considered
    // for search purposes is the vessel itself, otherwise use the parent body.
    local origin is choose ship if settings:origin_type = "vessel" else ship:body.

    // Use different defaults for asteroids and comets.
    local hyperbolic is destination:orbit:eccentricity >= 1.
    local extrasolar is hyperbolic and not destination:body:hasbody.

    // Calculate any default settings values using simple rules-of-thumb.
    local now is time():seconds.

    local earliest_departure is settings:earliest_departure.
    if earliest_departure = "default" {
        set earliest_departure to now + 120.
    }

    local search_duration is settings:search_duration.
    if search_duration = "default" {
        if extrasolar {
            set search_duration to origin:orbit:period.
        }
        else if hyperbolic {
            set search_duration to 0.5 * (rsvp:time_at_soi_edge(destination) - now).
        }
        else {
            local max_period is rsvp:max_period(origin, destination).
            local synodic_period is rsvp:synodic_period(origin, destination).
            set search_duration to max(max_period, synodic_period).
        }
    }

    local max_time_of_flight is settings:max_time_of_flight.
    if max_time_of_flight = "default" {
        if extrasolar {
            set max_time_of_flight to origin:orbit:period.
        }
        else if hyperbolic {
            set max_time_of_flight to 0.5 * (rsvp:time_at_soi_edge(destination) - now).
        }
        else {
            set max_time_of_flight to rsvp:ideal_hohmann_transfer_period(origin, destination).
        }
    }

    local search_interval is settings:search_interval.
    if search_interval = "default" {
        if extrasolar or hyperbolic {
            set search_interval to 0.5 * origin:orbit:period.
        }
        else {
            set search_interval to 0.5 * rsvp:min_period(origin, destination).
        }
    }

    local search_threshold is max(120, min(0.002 * search_interval, 3600)).

    // Build cost function.
    local transfer_details is rsvp:build_transfer_details(origin, destination, settings).

    // Find lowest deltav transfer.
    local craft_transfer is iterated_local_search(
        settings:verbose,
        earliest_departure,
        search_duration,
        max_time_of_flight,
        search_interval,
        search_threshold,
        transfer_details).

    // Re-run the Lambert solver to obtain deltav values.
    local details is transfer_details(craft_transfer:flip_direction, craft_transfer:departure_time, craft_transfer:arrival_time).

    // Construct nested result structure
    local departure is lex("time", craft_transfer:departure_time, "deltav", details:ejection).
    local arrival is lex("time", craft_transfer:arrival_time, "deltav", details:insertion).
    local predicted is lex("departure", departure, "arrival", arrival).
    local result to lex("success", true, "predicted", predicted).

    return lex("transfer", craft_transfer, "result", result).
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

    local x is earliest_departure.
    local latest_departure is earliest_departure + search_duration.

    // The default max_time_of_flight is twice the ideal Hohmann transfer time,
    // so setting the intial guess to half of that will be reasonably close to
    // the final value in most cases.
    local y is max_time_of_flight * 0.5.
    // The porkchop plot is not scaled evenly in the x and y dimensions.
    // Especially for transfers with a very large ratio between the periapsis
    // and apoapsis (for example Moho to Eeloo) each search interval is tall
    // and narrow. The step size is based on the x direction, so can be slow
    // when the hill climb algorithm is searching in the y direction. To speed
    // up the search, scale the step_size in the y direction.
    // The width of the search space is 3 search intervals (see min_x and
    // max_x declarations below) and the height is max_time_of_flight.
    local step_size is search_interval * 0.1.
    local scale_y is max_time_of_flight / (3 * search_interval).

    // Sneaky trick here. When comparing a scalar and a string, kOS converts the
    // scalar to a string then compares them lexicographically.
    // This means that *any* number will always be less than the string "max"
    // as "m" is a higher codepoint than the numeric digits 0-9.
    local result is lex("total_deltav", "max").
    local invocations is 0.

    until x > latest_departure {
        // Restrict x to a limited range of the total search space to save time.
        // If x wanders too far from its original value, then most likely the
        // previous search has already found that minimum or the next search will
        // find it.
        local min_x is max(earliest_departure, x - search_interval).
        local max_x is min(latest_departure, x + 2 * search_interval).

        // Calculate the intial delta-v value at the starting point and also figure
        // out which direction we should be going.
        local prograde_deltav is cost(false, v(x, y, 0)).
        local retrograde_deltav is cost(true, v(x, y, 0)).
        local flip_direction is retrograde_deltav < prograde_deltav.
        local initial_deltav is choose retrograde_deltav if flip_direction else prograde_deltav.

        function cost {
            parameter flip_direction, v1.

            // y is always bounded to the interval [0, max_time_of_flight]
            if v1:x < min_x or v1:x > max_x or v1:y < 0 or v1:y > max_time_of_flight {
                return "max".
            }
            else {
                set invocations to invocations + 1.
                local details is total_deltav(flip_direction, v1:x, v1:x + v1:y).
                return details:ejection + details:insertion.
            }
        }

        // Start a search from this location, updating "result" if "candidate" delta-v is lower.
        local candidate is rsvp:grid_search(cost@:bind(flip_direction), x, y, scale_y, initial_deltav, step_size, step_threshold).
        local departure_time is candidate:position:x.
        local arrival_time is candidate:position:x + candidate:position:y.
        local total_deltav is candidate:minimum.

        if verbose {
            print "Search offset: " + seconds_to_kerbin_time(x).
            print "  Departure: " + seconds_to_kerbin_time(departure_time).
            print "  Arrival: " + seconds_to_kerbin_time(arrival_time).
            print "  Delta-v: " + safe_round(total_deltav).
        }

        if total_deltav < result:total_deltav {
            set result to lex(
                "departure_time", departure_time,
                "arrival_time", arrival_time,
                "total_deltav", total_deltav,
                "flip_direction", flip_direction
            ).
        }

        set invocations to invocations + 2.
        set x to x + search_interval.
    }

    if verbose {
        print "Invocations: " + invocations.
        print "Best Result".
        print "  Departure: " + seconds_to_kerbin_time(result:departure_time).
        print "  Arrival: " + seconds_to_kerbin_time(result:arrival_time).
        print "  Delta-v: " + safe_round(result:total_deltav).
    }

    return result.
}

// Convert epoch seconds to human readable string.
local function seconds_to_kerbin_time {
    parameter seconds.

    local time_span is time(seconds).

    return time_span:calendar + " " + time_span:clock.
}

// Safely round a variable that could be a string
local function safe_round {
    parameter x.

    return choose round(x) if x:istype("scalar") else x.
}