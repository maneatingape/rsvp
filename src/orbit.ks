@lazyglobal off.

parameter export.
export("transfer_deltav", transfer_deltav@).
export("orbital_state_vectors", orbital_state_vectors@).
export("equatorial_ejection_deltav", equatorial_ejection_deltav@).
export("vessel_ejection_deltav", vessel_ejection_deltav@).
export("vessel_ejection_deltav_from_body", vessel_ejection_deltav_from_body@).
export("circular_insertion_deltav", orbit_insertion_deltav@:bind(true)).
export("elliptical_insertion_deltav", orbit_insertion_deltav@:bind(false)).
export("vessel_insertion_deltav", vessel_insertion_deltav@).
export("none_insertion_deltav", none_insertion_deltav@).
export("minimum_escape_velocity", minimum_escape_velocity@).
export("ideal_hohmann_transfer_period", ideal_hohmann_transfer_period@).
export("synodic_period", synodic_period@).
export("max_period", max_period@).
export("min_period", min_period@).
export("time_at_periapsis", time_at_periapsis@).
export("time_at_soi_edge", time_at_soi_edge@).
export("duration_from_soi_edge", duration_from_soi_edge@).
export("offset_from_soi_edge", offset_from_soi_edge@).

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

    return lex("dv1", dv1, "dv2", dv2, "osv1", osv1).
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
    local craft_velocity is velocityat(orbitable, epoch_time):orbit.

    return lex("position", position, "velocity", craft_velocity).
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
    parameter origin, craft_altitude, transfer_details.

    local mu is origin:mu.
    local r1 is origin:radius + craft_altitude.
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

// Vessels have no SOI or gravity so the delta-v required is exactly the
// transfer orbit departure or arrival delta-v.
local function vessel_ejection_deltav {
    parameter origin, craft_altitude, transfer_details.

    return transfer_details:dv1:mag.
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

    local v2 is departure_deltav:mag.
    local ve is sqrt(v2 ^ 2 + mu * (2 / r1 - 2 / r2)).

    // Calculate the eccentricity and semi-major axis of the escape hyperbola
    // (or possibly ellipse as KSP "chops" off the top of an ellipse once past
    // SOI, so you can escape even if mathematically the orbit is not a hyperbola).
    local e is ve ^ 2 * r1 / mu - 1.
    local a is r1 / (1 - e).
    // Calculate hyperbolic eccentric anomaly at a distance r2 from the focus.
    local cosh_E is (a - r2) / (a * e).
    // Slope of the velocity at a distance r2 from the focus:
    // dy =  b * cosh(E)
    // dx = -a * sinh(E)
    // dy / dx = (b / -a) * cosh(E) / sinh(E)
    // Replace (b / -a) with sqrt(e ^ 2 - 1)
    // Replace sinh(E) with sqrt(cosh(E) ^ 2 - 1)
    local m is cosh_E * sqrt((e ^ 2 - 1) / (cosh_E ^ 2 - 1)).

    // Now that we know the angle that the origin bends our escape trajectory,
    // we work backwards to determine the initial escape velocity vector.
    // Starting with the desired transfer velocity at SOI edge given by
    // "departure_deltav", we first invert the rotation acquired during escape,
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
    parameter is_circular, destination, craft_altitude, arrival_velocity.

    local mu is destination:mu.
    local r1 is destination:radius + craft_altitude.
    local r2 is destination:soiradius.

    // For elliptical orbits set apoapsis to 99% of the SOI radius
    // in order to leave some wiggle room.
    local a is choose r1 if is_circular else (r1 + 0.99 * r2) / 2.

    local v1 is sqrt(mu * (2 / r1 - 1 / a)).
    local v2 is arrival_velocity:mag.
    local ve is sqrt(v2 ^ 2 + mu * (2 / r1 - 2 / r2)).

    return ve - v1.
}

// Vessels have no SOI or gravity so the delta-v required is exactly the
// transfer orbit departure or arrival delta-v.
local function vessel_insertion_deltav {
    parameter destination, craft_altitude, arrival_velocity.

    return arrival_velocity:mag.
}

// Calculate the delta-v required for a flyby, aerocapture or extreme lithobrake...
local function none_insertion_deltav {
    parameter destination, craft_altitude, arrival_velocity.

    return 0.
}

// Calculate the minimum velocity that a craft can leave its current SOI with.
// As all KSP SOIs are finite, this will always be non-zero. For most planets
// this will be less than the minimum Hohmann transfer velocity to the nearest
// neighbour.
//
// For some moons with very large SOIs relative to their orbits this value will
// be *greater*. For example, Laythe's minimum escape velocity is higher than
// a direct Hohmann transfer to Vall, and even higher than a Hohmann transfer
// to Tylo at certain phase angles.
//
// For maximum safety factor this assumes that the ejection burn takes place at
// the current apoapsis, giving the maximum possible value. If the ejection burn
// takes place anywhere else on the orbit, then the actual value will be lower.
local function minimum_escape_velocity {
    parameter celestial_body, craft_altitude.

    local mu is celestial_body:mu.
    local r1 is celestial_body:radius + craft_altitude.
    local r2 is celestial_body:soiradius.

    local a is (r1 + r2) / 2.
    local ve is sqrt(mu * (2 / r2 - 1 / a)).

    return ve.
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

// Calculate the time at periapsis from orbital parameters. Hyperbolic intercept
// orbits will have a negative semi-majoraxis and negative mean anomaly at epoch.
// The mean anomaly increases to zero as the object approaches periapsis, then
// becomes positive and continously increasing until the object leaves the SOI.
local function time_at_periapsis {
    parameter craft_orbit.

    // By definition, mean anomaly is zero at periapsis.
    return time_at_mean_anomaly(craft_orbit, 0).
}

// Calculate the universal time for an object at a certain point in an orbit
// given the mean anomaly at that point.
local function time_at_mean_anomaly {
    parameter craft_orbit, M.

    // Calculate mean motion "n" using absolute value of semi-majoraxis
    // to handle both elliptical and hyperbolic cases
    local mu is craft_orbit:body:mu.
    local a is craft_orbit:semimajoraxis.
    local n is sqrt(mu / abs(a ^ 3)).

    // Get reference mean anomaly and epoch time.
    local t0 is craft_orbit:epoch.
    local M0 is craft_orbit:meananomalyatepoch * constant:degtorad. // Careful with units

    // Calculate mean anomaly difference, clamping to the range [0, 2π]
    // so that all times are in the future.
    local delta_M is M - M0.
    if delta_M < 0 {
        set delta_M to delta_M + 2 * constant:pi.
    }

    return t0 + delta_M / n.
}

// Calculate the time at which an object on a hyperbolic orbit will leave its
// current SOI. Positive mean anomaly is when the object is past periapsis and
// heading towards the edge of the SOI.
local function time_at_soi_edge {
    parameter destination.

    local r2 is destination:body:soiradius.
    local destination_orbit is destination:orbit.
    local a is destination_orbit:semimajoraxis.
    local e is destination_orbit:eccentricity.

    // Calculate mean anomaly from eccentric anomaly using hyperbolic variant
    // of Keplers' equation.
    local cosh_H is (a - r2) / (a * e).
    local sinh_H is sqrt(cosh_H ^ 2 - 1).
    local H is ln(cosh_H + sinh_H).
    local M is e * sinh_H - H.

    return time_at_mean_anomaly(destination_orbit, M).
}

// Calculate the time duration that a vessel will take from the edge of
// destination SOI to periapsis. This function is similar to the
// "time_at_soi_edge" function, the keys differences are:
// * Returns relative duration instead of an absolute time.
// * Derives the orbital parameters from arrival velocity and desired periapsis.
// * Handles both hyperbolic and elliptical injection orbits.
local function duration_from_soi_edge {
    parameter destination, craft_altitude, arrival_deltav.

    local mu is destination:mu.
    local r1 is destination:radius + craft_altitude.
    local r2 is destination:soiradius.

    local v2 is arrival_deltav:sqrmagnitude.
    local ve is v2 + mu * (2 / r1 - 2 / r2).

    local e is ve * r1 / mu - 1.
    local a is r1 / (1 - e).
    local n is sqrt(mu / abs(a ^ 3)).
    local M is "none".

    if e < 1 {
        local cos_E is (a - r2) / (a * e).
        local sin_E is sqrt(1 - cos_E ^ 2).
        local EA is arccos(cos_E) * constant:degtorad.
        set M to EA - e * sin_E.
    }
    else {
        local cosh_H is (a - r2) / (a * e).
        local sinh_H is sqrt(cosh_H ^ 2 - 1).
        local H is ln(cosh_H + sinh_H).
        set M to e * sinh_H - H.
    }

    return M / n.
}

// This function is based on the approach from the paper:
// "A new method of patched-conic for interplanetary orbit"
// by Jin Li, Jianhui Zhao and Fan Li
// https://doi.org/10.1016/j.ijleo.2017.10.153
//
// Given a velocity vector at SOI boundary, periapsis altitude and inclination,
// it derives the position vector "r" that satisifies the contraints.
// This position vector is combined in a feedback loop with the Lambert solver
// to refine the initial estimate from one that only considers planets as points
// to one that takes the SOI spheres into account.
//
// A key insight not in the original paper is that the minimum value of inclination
// can be derived from the equations for "h" and that using this value simplifies
// the equations considerably. As these equations use KSP's coordinate system,
// the x-z plane is the ecliptic and the y-axis is the north pole of the sun.
local function offset_from_soi_edge {
    parameter destination, craft_altitude, orientation, arrival_deltav.

    local mu is destination:mu.
    local r1 is destination:radius + craft_altitude.
    local r2 is destination:soiradius.

    local v1 is arrival_deltav.
    local v2 is v1:sqrmagnitude.
    local ve is sqrt(v2 + mu * (2 / r1 - 2 / r2)).

    // Specific angular momentum vector, chosen to minimize inclination.
    local h_mag is ve * r1.
    local n_mag is v1:x ^ 2 + v1:z ^ 2.
    local h is "none".

    if orientation = "polar" {
        set h to v(v1:z, 0, -v1:x) * (h_mag / sqrt(n_mag)).
    }
    else {
        local sign is choose 1 if orientation = "prograde" else -1.
        local cos_i is sign * sqrt(n_mag / v2).
        set h to v(-v1:x * v1:y / n_mag, 1, -v1:y * v1:z / n_mag) * (h_mag * cos_i).
    }

    // Given "v1", "h" and "delta" (the dot product of "r" and "v1")
    // derive the position vector "r".
    local delta is sqrt(v2 * r2 ^ 2 - h_mag ^ 2).
    local r_x is delta * v1:x + h:z * v1:y - h:y * v1:z.
    local r_y is delta * v1:y + h:x * v1:z - h:z * v1:x.
    local r_z is delta * v1:z + h:y * v1:x - h:x * v1:y.

    return v(r_x, r_y, r_z) / v2.
}