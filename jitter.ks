@lazyglobal off.

local directions is lexicon(
    "north", v(1, 0, 0),
    "south", v(-1, 0, 0),
    "east", v(0, 1, 0),
    "west", v(0, -1, 0),
    "up", v(0, 0, 1),
    "down", v(0, 0, -1)
).

global function coordinate_descent {
    parameter node, intercept_distance.

    local step_size is 1.
    local step_threshold is 0.001.
    local step_factor is 0.5.

    local distance is intercept_distance().
    local current_vector is v(node:radialout, node:normal, node:prograde).
    local next_vector is current_vector.
    local direction is "none".

    local original_distance is distance.
    local original_deltav is node:deltav:mag.

    local function set_node {
        parameter v.
        set node:radialout to v:x.
        set node:normal to v:y.
        set node:prograde to v:z.
    }

    local function cost {
        parameter test_direction, delta.

        local test_vector is current_vector + step_size * delta.
        set_node(test_vector).
        local test_distance is intercept_distance().

        if test_distance < distance {
            set distance to test_distance.
            set next_vector to test_vector.
            set direction to test_direction.
        }
        else if direction = test_direction {
            set direction to "none".
        }
    }

    until step_size < step_threshold {
        if directions:haskey(direction) {
            cost(direction, directions[direction]).
        }
        else {
            for test_direction in directions:keys {
                cost(test_direction, directions[test_direction]).
            }
        }

        set current_vector to next_vector.
        set_node(current_vector).

        if direction = "none" {
            set step_size to step_size * step_factor.
        }
    }

    return distance.
}