@lazyglobal off.

local directions is list(v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0), v(0, 0, 1), v(0, 0, -1)).

global function coordinate_descent {
    parameter intercept_distance, position.

    local invocations is 0.
    local initial_cost is cost(position).
    local step_size is 1.
    local step_threshold is 0.001.

    local function cost {
        parameter v.
        set invocations to invocations + 1.
        return intercept_distance(v).
    }

    return inner(cost@, position, initial_cost, step_size, step_threshold).
}

local function inner {
    parameter cost, position, minimum, step_size, step_threshold.

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
            for test_direction in directions {
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

    return lexicon("position", position, "minimum", minimum).
}