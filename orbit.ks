@lazyglobal off.
runoncepath("0:/rsvp/lambert.ks").

// Calculates the delta-v needed to transfer between origin and destination
// planets at the specified times.
//
// Parameters:
// origin [Body] Departure planet that vessel will leave from.
// destination [Body] Destination planet that vessel will arrive at.
// flip_direction [Boolean] Change transfer direction between prograde/retrograde
// departure [Scalar] Departure time in seconds from epoch
// arrival [Scalar] Arrival time in seconds from epoch
global function transfer_deltav {
    parameter origin, destination, flip_direction, departure, arrival.

    local position_offset is origin:body:position.
    local mu is origin:body:mu.

    // To determine the position of a planet at a specific time "t" relative to
    // its parent body using the "positionat" function, you must subtract the
    // *current* position of the parent body, not the position of the parent
    // body at time "t" as might be expected.
    local r1 is positionat(origin, departure) - position_offset.
    local r2 is positionat(destination, arrival) - position_offset.

    // Now that we know the positions of the planets at our departure and
    // arrival time, solve Lambert's problem to determine the velocity of the
    // transfer orbit that links the planets at both positions.
    local solution is lambert(r1, r2, arrival - departure, mu, flip_direction).

    // "velocityat" already returns orbital velocity relative to the parent
    // body, so no further adjustment is needed.
    local v1 is velocityat(origin, departure):orbit.
    local v2 is velocityat(destination, arrival):orbit.
    local dv1 is solution:v1 - v1.
    local dv2 is v2 - solution:v2.

    // Unit vectors of origin prograde, radial and normal directions.
    local origin_prograde is v1:normalized.
    local origin_radial is r1:normalized.
    local origin_normal is vcrs(origin_prograde, origin_radial):normalized.

    // Components of departure delta-v relative to origin direction.
    local prograde is vdot(origin_prograde, dv1).
    local radial is vdot(origin_radial, dv1).
    local normal is vdot(origin_normal, dv1).

    return lexicon(
        "prograde", prograde,
        "radial", radial,
        "normal", normal,
        "dv1", dv1,
        "dv2", dv2
    ).
}

// Calculate the delta-v required to eject into a hyperbolic transfer orbit
// at the correct inclination from the desired radius "r1".
// Simplifying assumptions:
// * Vessel is currently in a perfectly circular equatorial orbit at radius "r1"
//   and velocity "v1" at 0 degrees inclination.
// * The distance to the SOI edge from the center of the planet is small enough
//   (relative to the interplanetary transfer distance) that we can assume the
//   position at SOI edge is a close enough approximation to the position
//   supplied to the Lambert solver.
//
// In KSP's coordinate system, the positive y axis sticks straight up from
// Kerbol's north pole. Therefore the desired angle "i" between the
// flat circular orbit and the inclined ejection orbit is the angle between
// the original transfer velocity vector and the same vector with the
// y coordinate zeroed out.
//
// Our required delta-v, "v1" and 've" form a triangle with angle "i" between
// sides 'v1" and "ve'. The length of the 3rd side is the magnitude of our required
// delta-v and can be determined using the cosine rule. We calculate the cosine
// directly from the magnitudes of "v2" and the adjusted v2 with zero y component.
//
// The "body_insertion_deltav" function comment contains details on
// the formulas used to calculate "v1" and "ve".
global function equatorial_ejection_deltav {
    parameter origin, altitude, transfer_details.

    local mu is origin:mu.
    local r1 is origin:radius + altitude.
    local r2 is origin:soiradius.

    local v1 is sqrt(mu / r1).
    local v2 is transfer_details:dv1:mag.
    local ve is sqrt(v2 ^ 2 + mu * (2 / r1 - 2 / r2)).

    local hypot is sqrt(transfer_details:prograde ^ 2 + transfer_details:radial ^ 2).
    local normal_cos is hypot / v2.
    local ejection_deltav is sqrt(ve ^ 2 + v1 ^ 2 - 2 * ve * v1 * normal_cos).

    return ejection_deltav.
}

// Calculates the delta-v required for a vessel to eject into the desired
// transfer orbit, using its actual current orbit. As the vessel climbs out of
// the gravity well of the origin there are two effects to consider:
// * It slows down as it trades kinetic energy for potential energy, so that
//   initial excess velocity must be higher than our desired transfer velocity.
// * The gravity of the origin bends our trajectory as we escape, so that the
//   initial velocity vector must be adjusted to compensate.
global function vessel_ejection_deltav_from_origin {
    parameter vessel, transfer_details, clock.

    local origin is vessel:body.
    local velocity is velocityat(vessel, clock):orbit.
    local position is positionat(vessel, clock) - origin:position.
    local normal is vcrs(velocity, position).

    local mu is origin:mu.
    local r1 is position:mag.
    local r2 is origin:soiradius.

    local v1 is velocity:mag.
    local v2 is transfer_details:dv1:mag.
    local ve is sqrt(v2 ^ 2 + mu * (2 / r1 - 2 / r2)).

    // Calculate the eccentricity and semi-major axis of the escape hyperbola
    // (or possibly ellipse as KSP "chops" off the top of an ellipse once past
    // SOI, so you can escape even if mathematically the orbit is not a hyperbola).
    local e is ve ^ 2 * r1 / mu - 1.
    local a is r1 / (1 - e).
    // Cosine of the eccentric anomaly at a distance r2 from the focus
    local cos_ea is (a - r2) / (e * a).
    // Slope of the velocity at a distance r2 from the focus        
    local m is cos_ea * sqrt((1 - e ^ 2) / (1 - cos_ea ^ 2)).

    // Now that we know the angle that the origin bends our escape trajectory,
    // we work backwards to determine the initial escape velocity vector.
    // Starting with the desired transfer vecocity at SOI edge given by
    // "transfer_details:dv1", we first invert the rotation acquired during escape,
    // then scale by the appropriate factor and finally subtract the vessel's
    // current velocity to give the delta-v required.
    local slope_angle is 90 - arctan(m).
    local inverse_rotation is angleaxis(slope_angle, normal).
    local ejection is (ve / v2) * transfer_details:dv1 * inverse_rotation.

    return ejection - velocity.
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
global circular_insertion_deltav is body_insertion_deltav@:bind(true).
global elliptical_insertion_deltav is body_insertion_deltav@:bind(false).

local function body_insertion_deltav {
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
global function vessel_ejection_deltav {
    parameter origin, altitude, transfer_details.

    return transfer_details:dv1:mag.
}

global function vessel_insertion_deltav {
    parameter destination, altitude, transfer_details.

    return transfer_details:dv2:mag.
}

// Calculates the delta-v required for a flyby, aerocapture
// or extreme lithobrake...
global function no_insertion_deltav {
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
global function ideal_hohmann_transfer_period {
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
global function synodic_period {
    parameter origin, destination.

    local p1 is origin:orbit:period.
    local p2 is destination:orbit:period.

    return abs(p1 * p2 / (p1 - p2)).
}

// Returns the maximum period of either the origin or destination.
global function max_period {
    parameter origin, destination.

    return max(origin:orbit:period, destination:orbit:period).
}

// Returns the minimum period of either the origin or destination.
global function min_period {
    parameter origin, destination.

    return min(origin:orbit:period, destination:orbit:period).
}