@lazyglobal off.

parameter export.
export("vessel_to_vessel", vessel_to_vessel@).
export("vessel_to_body", vessel_to_body@).
export("body_to_vessel", body_to_vessel@).
export("body_to_body", body_to_body@).

// Vessel to vessel rendezvous (asteroids and comets also technically count
// as vessels) within the same SOI is the most straightforward case. The values
// from the Lambert solver are more than accurate enough to be used directly
// resulting in very precise intercepts, even over interplanetary distances.
local function vessel_to_vessel {
    parameter destination, settings, craft_transfer, result.

    // Calculate transfer orbit details from search result
    local flip_direction is craft_transfer:flip_direction.
    local departure_time is craft_transfer:departure_time.
    local arrival_time is craft_transfer:arrival_time.
    local details is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time).

    // 1st node
    local maneuver is create_vessel_node(departure_time, details:dv1).
    local departure is lex("time", departure_time, "deltav", details:dv1:mag).
    result:add("actual", lex("departure", departure)).

    // Check for unexpected encounters
    local expected_patches is list(ship:body).
    local validate_patches is maneuver:validate_patches(expected_patches, arrival_time).

    if not validate_patches:success {
        return validate_patches.
    }

    // 2nd node
    if settings:create_maneuver_nodes = "both" {
        create_vessel_node(arrival_time, details:dv2).
        local arrival is lex("time", arrival_time, "deltav", details:dv2:mag).
        result:actual:add("arrival", arrival).
    }

    return result.
}

// Vessel to body rendezvous requires some tweaking in order for the ship
// to avoid colliding directly with the center of the destination.
local function vessel_to_body {
    parameter destination, settings, craft_transfer, result.

    // Calculate transfer orbit details from search result. This transfer will be
    // *too* accurate with a trajectory that collides with the center of the body.
    local flip_direction is craft_transfer:flip_direction.
    local departure_time is craft_transfer:departure_time.
    local arrival_time is craft_transfer:arrival_time.
    local details is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time).

    // Refine the transfer, taking destination's SOI into account.
    local delta is 1.
    local iterations is 0.
    local final_orbit_periapsis is settings:final_orbit_periapsis.
    local final_orbit_orientation is settings:final_orbit_orientation.

    until delta < 0.01 or iterations = 15 {
        local offset is rsvp:offset_from_soi_edge(destination, final_orbit_periapsis, final_orbit_orientation, details:dv2).
        local duration is rsvp:duration_from_soi_edge(destination, final_orbit_periapsis, details:dv2).

        local next is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time - duration, ship:body, offset).
        local delta is (next:dv2 - details:dv2):mag.

        set details to next.
        set iterations to iterations + 1.
    }

    // Create initial maneuver node
    local maneuver is create_vessel_node(departure_time, details:dv1).

    // Check for unexpected encounters
    local expected_patches is list(ship:body, destination).
    local validate_patches is maneuver:validate_patches(expected_patches, arrival_time).

    if not validate_patches:success {
        return validate_patches.
    }

    // Add actual departure deltav to the result. This will differ slightly
    // from the predicted value due to the offset tweaks.
    local departure is lex("time", departure_time, "deltav", maneuver:deltav()).
    result:add("actual", lex("departure", departure)).

    // 2nd node
    if settings:create_maneuver_nodes = "both" {
        local arrival is create_body_arrival_node(destination, settings, maneuver).
        result:actual:add("arrival", arrival).
    }

    return result.
}

// Vessel to body rendezvous is not as accurate as other transfer types, so a
// correction burn is recommended once in interplanetary space.
local function body_to_vessel {
    parameter destination, settings, craft_transfer, result.

    // 1st node
    local maybe is create_body_departure_node(false, destination, settings, craft_transfer).

    // Node creation could fail due to unexpected encounter
    if not maybe:success {
        return maybe.
    }

    // Check for unexpected encounters
    local maneuver is maybe:maneuver.
    local expected_patches is list(ship:body, ship:body:body).
    local arrival_time is craft_transfer:arrival_time.
    local validate_patches is maneuver:validate_patches(expected_patches, arrival_time).

    if not validate_patches:success {
        return validate_patches.
    }

    // Add actual departure deltav to the result. This will differ quite a bit
    // from the predicted value due to the difficulties ejecting from a body
    // exactly at the predicted time and orientation.
    local departure is lex("time", maneuver:time(), "deltav", maneuver:deltav()).
    result:add("actual", lex("departure", departure)).

    // 2nd node
    if settings:create_maneuver_nodes = "both" {
        local osv1 is rsvp:orbital_state_vectors(ship, arrival_time).
        local osv2 is rsvp:orbital_state_vectors(destination, arrival_time).
        local deltav is osv2:velocity - osv1:velocity.
        create_vessel_node(arrival_time, deltav).

        local arrival is lex("time", arrival_time, "deltav", deltav:mag).
        result:actual:add("arrival", arrival).
    }

    return result.
}

// Body to body rendezvous is reasonably accurate as the predicted intercept
// can be used to refine the initial transfer.
local function body_to_body {
    parameter destination, settings, craft_transfer, result.

    // 1st node
    local maybe is create_body_departure_node(true, destination, settings, craft_transfer).

    // Node creation could fail due to unexpected encounter
    if not maybe:success {
        return maybe.
    }

    // Check for unexpected encounters
    local maneuver is maybe:maneuver.
    local expected_patches is list(ship:body, ship:body:body, destination).
    local arrival_time is craft_transfer:arrival_time.
    local validate_patches is maneuver:validate_patches(expected_patches, arrival_time).

    if not validate_patches:success {
        return validate_patches.
    }

    // Add actual departure deltav to the result. This will differ somewhat
    // from the predicted value due to the difficulties ejecting from a body
    // exactly at the predicted time and orientation.
    set maneuver to maybe:maneuver.
    local departure is lex("time", maneuver:time(), "deltav", maneuver:deltav()).
    result:add("actual", lex("departure", departure)).

    // 2nd node
    if settings:create_maneuver_nodes = "both" {
        local arrival is create_body_arrival_node(destination, settings, maneuver).
        result:actual:add("arrival", arrival).
    }

    return result.
}

// Creates both departure and arrival nodes for vessels, as the steps are the
// same for both situations.
local function create_vessel_node {
    parameter epoch_time, deltav.

    return rsvp:create_maneuver(true, epoch_time, deltav).
}

// Create an arrival node for a body, using the various "final_orbit..."
// setttings to result in the desired orbit periapsis and shape.
local function create_body_arrival_node {
    parameter destination, settings, maneuver.

    local patch_details is maneuver:patch_details(destination).
    local soi_velocity is patch_details:soi_velocity.
    local periapsis_altitude is patch_details:periapsis_altitude.
    local periapsis_time is patch_details:periapsis_time.

    local insertion_deltav is rsvp[settings:final_orbit_type + "_insertion_deltav"].
    local deltav is insertion_deltav(destination, periapsis_altitude, soi_velocity).

    // Brake by the right amount at the right time.
    rsvp:create_raw_maneuver(false, periapsis_time, v(0, 0, -deltav)).

    return lex("time", periapsis_time, "deltav", deltav).
}

// Creates an ejection maneuver node by applying a feedback loop to refine it.
// The initial transfer will be incorrect as it assumes that the vessel
// is floating in free space and neglects the time taken to climb out of the
// origin planet's SOI.
// We re-calculate the transfer immediately after leaving the origin's SOI
// then feedback this error in order to correct our initial guess. This
// converges rapidly to an accurate intercept.
local function create_body_departure_node {
    parameter to_body, destination, settings, craft_transfer.

    local flip_direction is craft_transfer:flip_direction.
    local departure_time is craft_transfer:departure_time.
    local arrival_time is craft_transfer:arrival_time.

    local parent is ship:body.
    local grandparent is parent:body.
    local expected_patches is list(parent, grandparent).

    // Initial guess
    local details is rsvp:transfer_deltav(parent, destination, flip_direction, departure_time, arrival_time).
    local departure_deltav is details:dv1.
    local maneuver is create_maneuver_node_in_correct_location(departure_time, departure_deltav).

    // Refine the node
    local delta is v(1, 0, 0).
    local iterations is 0.
    local final_orbit_periapsis is settings:final_orbit_periapsis.
    local final_orbit_orientation is settings:final_orbit_orientation.
    local duration is 0.
    local offset is v(0, 0, 0).

    until delta:mag < 0.01 or iterations = 15 {
        // Expect the unexpected
        local patch_details is maneuver:patch_details(grandparent).
        local soi_time is choose "max" if patch_details = "none" else patch_details:soi_time.
        local validate_patches is maneuver:validate_patches(expected_patches, soi_time).

        if not validate_patches:success {
            return validate_patches.
        }

        // Take SOI into account
        if to_body {
            set offset to rsvp:offset_from_soi_edge(destination, final_orbit_periapsis, final_orbit_orientation, details:dv2).
            set duration to rsvp:duration_from_soi_edge(destination, final_orbit_periapsis, details:dv2).
        }

        // Calculate correction using predicted flight path
        local details is rsvp:transfer_deltav(ship, destination, flip_direction, soi_time, arrival_time - duration, grandparent, offset).

        // Update our current departure velocity with this correction.
        set delta to details:dv1.
        set iterations to iterations + 1.
        set departure_time to maneuver:time().
        set departure_deltav to departure_deltav + delta.

        // Apply the new node, rinse and repeat.
        maneuver:delete().
        set maneuver to create_maneuver_node_in_correct_location(departure_time, departure_deltav).
    }

    return lex("success", true, "maneuver", maneuver).
}

// Creates maneuver node at the correct location around the origin planet in
// order to eject at the desired orientation.
// Using the raw magnitude of the delta-v as our cost function handles
// mutliple situtations and edge cases in one simple robust approach.
// For example prograde/retrograde ejection combined with
// clockwise/anti-clockwise orbit gives at least 4 valid possibilities
// that need to handled.
//
// Additionaly this method implicitly includes the necessary adjustment
// to the manuever node position to account for the radial component
// of the ejection velocity.
//
// Finally it can handle non-perfectly circular and inclined orbits.
local function create_maneuver_node_in_correct_location {
    parameter departure_time, departure_deltav.

    function ejection_details {
        parameter cost_only, v1.

        local epoch_time is v1:x.
        local osv is rsvp:orbital_state_vectors(ship, epoch_time).
        local ejection_deltav is rsvp:vessel_ejection_deltav_from_body(ship:body, osv, departure_deltav).

        return choose ejection_deltav:mag if cost_only else ejection_deltav.
    }

    // Search for time in ship's orbit where ejection deltav is lowest.
    local cost is ejection_details@:bind(true).
    local result is rsvp:line_search(cost, departure_time, 120, 1).
    local ejection_deltav is ejection_details(false, result:position).

    return rsvp:create_maneuver(false, result:position:x, ejection_deltav).
}