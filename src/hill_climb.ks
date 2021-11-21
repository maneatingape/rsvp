@lazyglobal off.

parameter export.
export("line_search", line_search@).
export("grid_search", grid_search@).

// Convenience wrapper for searching a single dimension.
local function line_search {
    parameter cost, x, step_size, step_threshold.

    local dimensions is list(v(1, 0, 0), v(-1, 0, 0)).
    local position is v(x, 0, 0).
    local minimum is cost(position).

    return coordinate_descent(dimensions, cost, position, minimum, step_size, step_threshold).
}

// Convenience wrapper for searching two dimensions.
local function grid_search {
    parameter cost, x, y, scale_y, minimum, step_size, step_threshold.

    local dimensions is list(v(1, 0, 0), v(-1, 0, 0), v(0, scale_y, 0), v(0, -scale_y, 0)).
    local position is v(x, y, 0).

    return coordinate_descent(dimensions, cost, position, minimum, step_size, step_threshold).
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