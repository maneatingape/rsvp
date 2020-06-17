@lazyglobal off.

global function coordinate_descent {
    parameter node, intercept_distance.

    local step_size is 1.
    local step_threshold is 0.001.
    local step_factor is 0.5.

    local distance is intercept_distance().
    local current_vector is v(node:radialout, node:normal, node:prograde).
    local next_vector is current_vector.

    local directions is list(v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0), v(0, 0, 1), v(0, 0, -1)).    
    local direction is "none".

    local function set_node {
        parameter v.
        set node:radialout to v:x.
        set node:normal to v:y.
        set node:prograde to v:z.
    }

    local function cost {
        parameter test_direction.

        local test_vector is current_vector + step_size * test_direction.
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
        if direction = "none" {
            for test_direction in directions {
                cost(test_direction).
            }
        }
        else {
            cost(direction).
        }

        set current_vector to next_vector.
        set_node(current_vector).

        if direction = "none" {
            set step_size to step_size * step_factor.
        }
    }

    return distance.
}