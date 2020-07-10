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
    parameter destination, settings, transfer, result.

    // Calculate transfer orbit details from search result
    local flip_direction is transfer:flip_direction.
    local departure_time is transfer:departure_time.
    local arrival_time is transfer:arrival_time.
    local details is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time).

    // 1st node
    create_vessel_node(departure_time, details:dv1).
    local departure is lex("time", departure_time, "deltav", details:dv1:mag).
    result:add("actual", lex("departure", departure)).

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
    parameter destination, settings, transfer, result.

    // Calculate transfer orbit details from search result
    local flip_direction is transfer:flip_direction.
    local departure_time is transfer:departure_time.
    local arrival_time is transfer:arrival_time.
    local details is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time).

    // Create initial approximate maneuver node. This node will be *too* accurate
    // with a trajectory that collides with the center of the body.
    local maneuver is create_vessel_node(departure_time, details:dv1).

    // Using our arrival velocity at the edge of the destination's SOI, calculate
    // an initial guess for the "impact parameter", that is the distance that
    // we should offset in order to miss by roughly our desired periapsis.
    local final_orbit_periapsis is settings:final_orbit_periapsis.
    local final_orbit_orientation is settings:final_orbit_orientation.
    local encounter is maneuver:encounter_details(destination).
    local impact_parameter is rsvp:impact_parameter(destination, encounter, final_orbit_periapsis, final_orbit_orientation).

    // Refine our initial guess using a one-dimensional line search with feedback.
    local initial_guess is impact_parameter:factor.
    local step_size is 0.25 * initial_guess.
    local step_threshold is 100.
    local search is rsvp:line_search(cost@, initial_guess, step_size, step_threshold).

    function cost {
        parameter v.

        // Delete previous maneuver as it will affect orbit prediction.
        maneuver:delete().
        // Predict trajectory to destination, offset by test candidate vector.
        local candidate is v:x * impact_parameter:vector.
        local details is rsvp:transfer_deltav(ship, destination, flip_direction, departure_time, arrival_time, ship:body, candidate).
        // Create new node then check delta between desired and actual periapsis.
        set maneuver to create_vessel_node(departure_time, details:dv1).
        local encounter is maneuver:encounter_details(destination).

        if encounter <> "none" {
            return abs(final_orbit_periapsis - encounter:periapsis).
        }
        else {
            return "max".
        }
    }

    // Make sure maneuver node is last best position.
    cost(search:position).

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
function body_to_vessel {
    parameter destination, settings, transfer, result.

    // 1st node
    local flip_direction is transfer:flip_direction.
    local departure_time is transfer:departure_time.
    local arrival_time is transfer:arrival_time.
    local maneuver is create_body_departure_node(destination, flip_direction, departure_time, arrival_time).

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
    parameter destination, settings, transfer, result.

    // 1st node
    local flip_direction is transfer:flip_direction.
    local departure_time is transfer:departure_time.
    local arrival_time is transfer:arrival_time.
    local maneuver is create_body_departure_node(destination, flip_direction, departure_time, arrival_time).

    // Using our arrival velocity at the edge of the destination's SOI, calculate
    // an initial guess for the "impact parameter", that is the distance that
    // we should offset in order to miss by roughly our desired periapsis.
    local final_orbit_periapsis is settings:final_orbit_periapsis.
    local final_orbit_orientation is settings:final_orbit_orientation.
    local encounter is maneuver:encounter_details(destination).
    local periapsis_time is maneuver:periapsis_time(destination).
    local impact_parameter is rsvp:impact_parameter(destination, encounter, final_orbit_periapsis, final_orbit_orientation).

    // Adjust the intercept *once* using the initial impact parameter estimate.
    // Unlike the vessel_to_body case, an interative search provides no real
    // benefit and frequently makes things worse.
    // For most planets this gets reasonably close (within ~20%). If a more
    // precise transfer is needed then a followup correction burn can be
    // calculated once in interplantery space using the vessel_to_body function.
    local offset is impact_parameter:factor * impact_parameter:vector.
    maneuver:delete().
    set maneuver to create_body_departure_node(destination, flip_direction, departure_time, periapsis_time, offset).

    // Add actual departure deltav to the result. This will differ somewhat
    // from the predicted value due to the difficulties ejecting from a body
    // exactly at the predicted time and orientation.
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

    local osv is rsvp:orbital_state_vectors(ship, epoch_time).
    local projection is rsvp:maneuver_node_vector_projection(osv, deltav).

    return rsvp:create_maneuver(true, epoch_time, projection).
}

// Create an arrival node for a body, using the various "final_orbit..."
// setttings to result in the desired orbit periapsis and shape.
local function create_body_arrival_node {
    parameter destination, settings, maneuver.

    local encounter is maneuver:encounter_details(destination).
    local periapsis_time is maneuver:periapsis_time(destination).

    local insertion_deltav is rsvp[settings:final_orbit_type + "_insertion_deltav"].
    local deltav is insertion_deltav(destination, encounter:periapsis, encounter:velocity).

    // Brake by the right amount at the right time.
    add node(periapsis_time, 0, 0, -deltav).

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
    parameter destination, flip_direction, departure_time, arrival_time, offset is v(0, 0, 0).

    // Initial guess
    local grandparent is ship:body:body.
    local details is rsvp:transfer_deltav(ship:body, destination, flip_direction, departure_time, arrival_time, grandparent, offset).
    local departure_deltav is details:dv1.
    local maneuver is create_maneuver_node_in_correct_location(departure_time, departure_deltav).

    local delta is v(1, 0, 0).
    local iterations is 0.

    until delta:mag < 0.001 or iterations = 15 {
        // Calculate correction using predicted flight path
        local encounter is maneuver:encounter_details(grandparent).
        local details is rsvp:transfer_deltav(ship, destination, flip_direction, encounter:time, arrival_time, grandparent, offset).

        // Update our current departure velocity with this correction.
        set delta to details:dv1.
        set iterations to iterations + 1.
        set departure_time to maneuver:time().
        set departure_deltav to departure_deltav + delta.

        // Apply the new node, rinse and repeat.
        maneuver:delete().
        set maneuver to create_maneuver_node_in_correct_location(departure_time, departure_deltav).
    }

    return maneuver.
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
        parameter cost_only, v.

        local epoch_time is v:x.
        local osv is rsvp:orbital_state_vectors(ship, epoch_time).
        local ejection_deltav is rsvp:vessel_ejection_deltav_from_body(ship:body, osv, departure_deltav).

        return choose ejection_deltav:mag if cost_only else rsvp:maneuver_node_vector_projection(osv, ejection_deltav).
    }

    // Search for time in ship's orbit where ejection deltav is lowest.
    local cost is ejection_details@:bind(true).
    local result is rsvp:line_search(cost, departure_time, 120, 1).
    // Ejection velocity projected onto ship prograde, normal and radial vectors.
    local projection is ejection_details(false, result:position).

    return rsvp:create_maneuver(false, result:position:x, projection).
}