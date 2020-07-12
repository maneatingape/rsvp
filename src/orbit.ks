@lazyglobal off.

parameter export.
export("transfer_deltav", transfer_deltav@).
export("orbital_state_vectors", orbital_state_vectors@).
export("maneuver_node_vector_projection", maneuver_node_vector_projection@).
export("equatorial_ejection_deltav", equatorial_ejection_deltav@).
export("vessel_ejection_deltav_from_body", vessel_ejection_deltav_from_body@).
export("impact_parameter_offset", impact_parameter_offset@).
export("circular_insertion_deltav", orbit_insertion_deltav@:bind(true)).
export("elliptical_insertion_deltav", orbit_insertion_deltav@:bind(false)).
export("vessel_ejection_deltav", vessel_ejection_deltav@).
export("vessel_insertion_deltav", vessel_insertion_deltav@).
export("no_insertion_deltav", no_insertion_deltav@).
export("ideal_hohmann_transfer_period", ideal_hohmann_transfer_period@).
export("synodic_period", synodic_period@).
export("max_period", max_period@).
export("min_period", min_period@).

// Calculates the delta-v needed to transfer between origin and destination
// planets at the specified times.
//
// Simplifying assumption:
// * The distance to the SOI edge from the center of the planet is small enough
//   (relative to the interplanetary transfer distance) that we can assume the
//   position at SOI edge is a close enough approximation to the position
//   supplied to the Lambert solver.
//
// Parameters:
// origin [Body] Departure planet that vessel will leave from.
// destination [Body] Destination planet that vessel will arrive at.
// flip_direction [Boolean] Change transfer direction between prograde/retrograde
// departure [Scalar] Departure time in seconds from epoch
// arrival [Scalar] Arrival time in seconds from epoch
local function transfer_deltav {
    parameter origin, destination, flip_direction, departure_time, arrival_time, parent is origin:body, offset is v(0, 0, 0).

    local time_of_flight is arrival_time - departure_time.
    local osv1 is orbital_state_vectors(origin, departure_time, parent).
    local osv2 is orbital_state_vectors(destination, arrival_time, parent).

    local r1 is osv1:position.
    local r2 is osv2:position + offset.
    local mu is parent:mu.

    // Now that we know the positions of the planets at our departure and
    // arrival time, solve Lambert's problem to determine the velocity of the
    // transfer orbit that links the planets at both positions.
    local solution is rsvp:lambert(r1, r2, time_of_flight, mu, flip_direction).
    local dv1 is solution:v1 - osv1:velocity.
    local dv2 is osv2:velocity - solution:v2.

    return lexicon("dv1", dv1, "dv2", dv2, "osv1", osv1).
}

// Returns the cartesian orbital state vectors of position and velocity
// at any specified time in the present, past or future.
local function orbital_state_vectors {
    parameter orbitable, epoch_time, parent is orbitable:body.

    // To determine the position of a planet at a specific time "t" relative to
    // its parent body using the "positionat" function, you must subtract the
    // *current* position of the parent body, not the position of the parent
    // body at time "t" as might be expected.
    local position is positionat(orbitable, epoch_time) - parent:position.
    // "velocityat" already returns orbital velocity relative to the parent
    // body, so no further adjustment is needed.
    local velocity is velocityat(orbitable, epoch_time):orbit.

    return lexicon("position", position, "velocity", velocity).
}

// Returns the vector projection of a velocity vector onto the given orbital
// state vector. This comes in useful as most vectors use KSP's raw coordinate
// system, however maneuver node's prograde, radial and normal components are
// relative to the vessel's velocity and position *at the time of the node*.
local function maneuver_node_vector_projection {
    parameter osv, velocity.

    // Unit vectors in vessel prograde and normal directions.
    local unit_prograde is osv:velocity:normalized.
    local unit_normal is vcrs(osv:velocity, osv:position):normalized.
    // KSP quirk: Manuever node "radial" is not the usual meaning of radial
    // in the sense of a vector from the center of the parent body towards
    // the ship, but rather a vector orthogonal to prograde and normal vectors.
    local unit_radial is vcrs(unit_normal, unit_prograde).

    // Components of velocity parallel to respective unit vectors.
    local radial is vdot(unit_radial, velocity).
    local normal is vdot(unit_normal, velocity).
    local prograde is vdot(unit_prograde, velocity).

    return v(radial, normal, prograde).
}

// Calculate the delta-v required to eject into a hyperbolic transfer orbit
// at the correct inclination from the desired radius "r1".
//
// Simplifying assumption:
// * Vessel is currently in a perfectly circular equatorial orbit at radius "r1"
//   and velocity "v1" at 0 degrees inclination.
//
// Our required delta-v, "v1" and 've" form a triangle with angle "i" between
// sides 'v1" and "ve'. The length of the 3rd side is the magnitude of our required
// delta-v and can be determined using the cosine rule. We calculate the cosine
// directly from the magnitudes of "v2" and its normal component.
//
// The "body_insertion_deltav" function comment contains details on
// the formulas used to calculate "v1" and "ve".
local function equatorial_ejection_deltav {
    parameter origin, altitude, transfer_details.

    local mu is origin:mu.
    local r1 is origin:radius + altitude.
    local r2 is origin:soiradius.

    local v1 is sqrt(mu / r1).
    local v2 is transfer_details:dv1:mag.
    local ve is sqrt(v2 ^ 2 + mu * (2 / r1 - 2 / r2)).

    local osv1 is transfer_details:osv1.
    local unit_normal is vcrs(osv1:velocity, osv1:position):normalized.
    local normal_component is vdot(unit_normal, transfer_details:dv1).

    local sin_i is normal_component / v2.
    local cos_i is sqrt(1 - sin_i ^ 2).
    local ejection_deltav is sqrt(ve ^ 2 + v1 ^ 2 - 2 * ve * v1 * cos_i).

    return ejection_deltav.
}

// Calculates the delta-v required for a vessel to eject into the desired
// transfer orbit, using its actual current orbit. As the vessel climbs out of
// the gravity well of the origin there are two effects to consider:
// * It slows down as it trades kinetic energy for potential energy, so that
//   initial excess velocity must be higher than our desired transfer velocity.
// * The gravity of the origin bends our trajectory as we escape, so that the
//   initial velocity vector must be adjusted to compensate.
local function vessel_ejection_deltav_from_body {
    parameter origin, osv, departure_deltav.

    local mu is origin:mu.
    local r1 is osv:position:mag.
    local r2 is origin:soiradius.

    local v1 is osv:velocity:mag.
    local v2 is departure_deltav:mag.
    local ve is sqrt(v2 ^ 2 + mu * (2 / r1 - 2 / r2)).

    // Calculate the eccentricity and semi-major axis of the escape hyperbola
    // (or possibly ellipse as KSP "chops" off the top of an ellipse once past
    // SOI, so you can escape even if mathematically the orbit is not a hyperbola).
    local e is ve ^ 2 * r1 / mu - 1.
    local a is r1 / (1 - e).
    // Cosine of the eccentric anomaly at a distance r2 from the focus:
    local cos_E is (a - r2) / (a * e).
    // Negative slope of the velocity at a distance r2 from the focus:
    // -dy = b * -cos(E)
    //  dx = a * -sin(E)
    // -dy / dx = (b / a) * cos(E) / sin (E)
    // Replace (b / a) with sqrt(1 - e ^ 2)
    // Replace sin(E) with sqrt(1 - cos(E)^2)
    local m is cos_E * sqrt((1 - e ^ 2) / (1 - cos_E ^ 2)).

    // Now that we know the angle that the origin bends our escape trajectory,
    // we work backwards to determine the initial escape velocity vector.
    // Starting with the desired transfer vecocity at SOI edge given by
    // "transfer_details:dv1", we first invert the rotation acquired during escape,
    // then scale by the appropriate factor and finally subtract the vessel's
    // current velocity to give the delta-v required.
    //
    // "slope_angle" is exactly 90 degrees in the case of a parabolic ejection
    // (barely escaping, eccentricity is 1) and approaches 0 degrees as the
    // hyperbolic excess velocity and eccentricity tends to infinity.
    //
    // Additionally for the special case in KSP where you can escape with an
    // mathematically elliptical orbit (impossible in real life, however KSP
    // "chops" off the top of an orbit once you exceed SOI radius)
    // the angle is greater than 90 degrees. For example, a situation where this
    // can occur is during a Laythe to Tylo transfer.
    local slope_angle is 90 - arctan(m).
    local ship_normal is vcrs(osv:velocity, osv:position).
    local inverse_rotation is angleaxis(slope_angle, ship_normal).
    local ejection_velocity is (ve / v2) * departure_deltav * inverse_rotation.

    return ejection_velocity - osv:velocity.
}

// Calculates the impact parameter offset. The impact parameter is the distance
// that the vessel would miss the destination if there was no gravity in its SOI.
// Approaching on a hyperbolic trajectory from infinity this is simply "b"
// the semi-minor axis.
//
// This is slightly incorrect for KSP's finite SOIs, but is close enough to make
// a good initial guess when tweaking the intercept for a desired periapsis.
// This figure is used to scale a vector offset from the planet's center that
// will result in an orbit periapsis in the correct location.
local function impact_parameter_offset {
    parameter destination, arrival_time, arrival_velocity, altitude, orientation.

    local mu is destination:mu.
    local r1 is destination:radius + altitude.
    local r2 is destination:soiradius.

    local v2 is arrival_velocity:mag.

    local a is 1 / (2 / r2 - v2 ^ 2 / mu).
    local e is 1 - r1 / a.
    // Handle both hyperbolic and elliptical cases
    local b is abs(a) * sqrt(abs(1 - e ^ 2)).

    local osv is orbital_state_vectors(destination, arrival_time).
    local normal is vcrs(osv:velocity, osv:position):normalized.
    local radial is vcrs(normal, arrival_velocity):normalized.

    local orientation_vectors is lexicon("prograde", radial, "polar", normal, "retrograde", -radial).
    local offset_vector is orientation_vectors[orientation].

    return lexicon("factor", b, "vector", offset_vector).
}

// Calculate the delta-v required to convert a hyperbolic intercept orbit
// into a circular or elliptical orbit around the target planet
// with the desired periapsis.
//
// To simplify calculations no inclination change is made, so that the delta-v
// required will simply be the difference between the hyperbolic velocity
// at "r1" and the elliptical orbital velocity at "r1".
//
// For an elliptical orbit at radius "r1" the orbital velocity "v1" is
// straightforward to calculate using the vis-viva equation. Circular orbits
// are a special case with semi-major axis equal to the final altitude.
//
// Calculating the hyperbolic velocity (denoted "ve") at "r1" is more fun
// and can be determined by applying the vis-visa equation twice.
// Our velocity "v2" at the edge of the SOI (radius denoted "r2") can be
// closely approximated as the magnitude of the "transfer_details:dv2" vector.
//
// The vis-viva equation states that:
// [Equation 1] v2 ^ 2 = mu * (2 / r2 - 1 / a)
//
// Re-arranging gives:
// [Equation 2] -1 / a = (v2 ^ 2) / mu - 2 / r2
//
// Applying the equation again at "r1" gives:
// [Equation 3] v ^ 2 = mu * (2 / r1 - 1 / a)
//
// Substituting 2 into 3 gives:
// [Equation 4] v ^ 2 = mu * (2 / r1 + (v2 ^ 2) / mu - 2 / r2)
//
// Re-arranging slightly:
// [Equation 5] v ^ 2 = (v2 ^ 2) + mu * (2 / r1 - 2 / r2)
//
// Taking the square root of equation 5 then subtracting 'v1" gives the delta-v
// required to capture into the desired orbit.
local function orbit_insertion_deltav {
    parameter is_circular, destination, altitude, transfer_details.

    local mu is destination:mu.
    local r1 is destination:radius + altitude.
    local r2 is destination:soiradius.

    local a is choose r1 if is_circular else (r1 + r2) / 2.

    local v1 is sqrt(mu * (2 / r1 - 1 / a)).
    local v2 is transfer_details:dv2:mag.
    local ve is sqrt(v2 ^ 2 + mu * (2 / r1 - 2 / r2)).

    return ve - v1.
}

// Vessels have no SOI or gravity so the delta-v required is exactly the
// transfer orbit departure or arrival delta-v.
local function vessel_ejection_deltav {
    parameter origin, altitude, transfer_details.

    return transfer_details:dv1:mag.
}

local function vessel_insertion_deltav {
    parameter destination, altitude, transfer_details.

    return transfer_details:dv2:mag.
}

// Calculates the delta-v required for a flyby, aerocapture
// or extreme lithobrake...
local function no_insertion_deltav {
    parameter destination, altitude, transfer_details.

    return 0.
}

// Calculate the time of flight for an idealized Hohmann transfer orbit between
// two planets. This provides an approximate initial guess when searching the
// solution space provided by the Lambert solver.
//
// Simplifying assumptions:
// * Both planet's orbits are circular (eccentricity is ignored).
// * Transfer angle is exactly 180 degrees.
//
// This means that the idealized transfer orbit is an elliptical orbit with a
// semi-major axis equal to the average of both planet's semi-major axes.
// The period can then be determined analytically using Kepler's 3rd law.
local function ideal_hohmann_transfer_period {
    parameter origin, destination.

    local a is (origin:orbit:semimajoraxis + destination:orbit:semimajoraxis) / 2.
    local mu is origin:body:mu.

    return 2 * constant:pi * sqrt(a ^ 3 / mu).
}

// Calculate the syndodic period. This is the time between conjunctions when
// both planets have the same ecliptic longtitude or alternatively when both
// planets return to the same phase angle. Eccentricity and inclination are
// not considered so the planets will not necessarily be in exactly the same
// three dimensional position relative to each other.
//
// The closer two planets' orbital period the longer the synodic period,
// approaching infinity as the orbital periods converge. Intuitively this makes
// sense. If two planets' orbits are exactly the same then they are always at
// the same phase angle.
//
// This value is included in the heuristic when determining the search duration
// to prevent it from being too short. For example two planets with short but
// similar orbital periods would have a long synodic period that needs to be
// searched to reliably return to lowest cost delta-v transfer.
local function synodic_period {
    parameter origin, destination.

    local p1 is origin:orbit:period.
    local p2 is destination:orbit:period.

    return abs(p1 * p2 / (p1 - p2)).
}

// Returns the maximum period of either the origin or destination.
local function max_period {
    parameter origin, destination.

    return max(origin:orbit:period, destination:orbit:period).
}

// Returns the minimum period of either the origin or destination.
local function min_period {
    parameter origin, destination.

    return min(origin:orbit:period, destination:orbit:period).
}