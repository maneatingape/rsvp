// This code is a kOS port of the PyKep project Lambert's problem solver,
// developed by the European Space Agency, available at
// https://github.com/esa/pykep
//
// The algorithm and equations are described in excellent detail in the paper
// "Revisiting Lambert’s problem" by Dario Izzio, available at
// https://www.esa.int/gsp/ACT/doc/MAD/pub/ACT-RPR-MAD-2014-RevisitingLambertProblem.pdf
//
// As a derivative work it is licensed under the GNU GPL 3.0, a copy of which
// is included in the root of this repository.
//
// The same variable names and structure used in the algorithm described in the
// paper and original C++ code are reused as much as possible.
//
// Major simplifying differences:
// * Multi-revolution transfer orbits are not considered
// * Time of flight is always calculated using Lagrange's formula
//
// Minor syntactical changes:
// * As kOS is case-insensitive and also to increase clarity, the magnitude of
//   the r1 and r2 vectors are denoted m1 and m2, rather than R1 and R2.
// * The original code reuses the name "tof", both for the user specified time
//   of flight and also for the iterative error when finding the value of "x".
//   To reduce confusion the second use case is denoted "tau" in this code.
// * kOS supports the exponential operator ^ so this is used instead of repeated
//   multiplication and division of intermediate variables.
//   This operator has the highest precedence, however in some complex equations
//   it is surrounded by parentheses in order to aid clarity.
// * kOS syntax supports vector multiplication and addition, considerably
//   simplifying the syntax when calculating v1 and v2.
// * kOS trignometric functions use degrees instead of radians. As all equations
//   in this algorithm expect radians, variants of the trignometric functions
//   that use radians are imported from the "util.ks" file, namespaced with "trig".
//   The standard hyperbolic trignometric functions are also defined in this file.

@lazyglobal off.
runoncepath("util.ks").

// r1 Vector first cartesian position
// r2 Vector second cartesian position
// tof Scalar seconds time of flight
// mu Scalar gravity parameter
// flip_direction Boolean Change transfer to prograde/retrograde
global function lambert {
	parameter r1, r2, tof, mu, flip_direction.

	local m1 is r1:mag.
	local m2 is r2:mag.
	local c is (r1 - r2):mag.
    local s is (m1 + m2 + c) / 2.
    local lambda is sqrt(1 - c / s).
    local t is tof * sqrt(2 * mu / s ^ 3).

    // Create unit vectors
    local ir1 is r1:normalized.
    local ir2 is r2:normalized.
    local ih is vcrs(ir1, ir2):normalized.
    local it1 is vcrs(ih, ir1):normalized.
    local it2 is vcrs(ih, ir2):normalized.

    if flip_direction {
    	set it1 to -it1.
    	set it2 to -it2.
    	set lambda to -lambda.
    }

    // Determine Lancaster-Blanchard variable "x"
    local x0 is initial_guess(lambda, t).
    local f is householders_method@:bind(lambda, t).
    local x is iterative_root_finder(x0, f, 1e-5, 15).

    // Construct velocity vectors from "x"
    local y is sqrt(1 - lambda ^ 2 * (1 - x ^ 2)).
    local rho is (m1 - m2) / c.
    local gamma is sqrt(mu * s / 2).

	local vr1 is (lambda * y - x) - rho * (lambda * y + x).
	local vr2 is (x - lambda * y) - rho * (lambda * y + x).
	local vt is sqrt(1 - rho ^ 2) * (y + lambda * x).

	local v1 is (gamma / m1) * (vr1 * ir1 + vt * it1).
	local v2 is (gamma / m2) * (vr2 * ir2 + vt * it2).
	return lexicon("v1", v1, "v2", v2).
}

local function initial_guess {
	parameter lambda, t.

    local t0 is trig:acos(lambda) + lambda * sqrt(1 - lambda ^ 2).
    local t1 is (2 / 3) * (1 - lambda ^ 3).

    if t >= t0 {
		return (t0 / t) ^ (2 / 3) - 1.
	} else if t <= t1 {
		return (5 * t1 * (t1 - t)) / (2 * t * (1 - lambda ^ 5)) + 1.
	} else {
		return (t0 / t) ^ (ln(t1 / t0) / ln(2)) - 1.
	}
}

local function householders_method {
    parameter lambda, t, x.

    local a is 1 / (1 - x ^ 2).
    local y is sqrt(1 - lambda ^ 2 * (1 - x ^ 2)).
    local tau is time_of_flight(lambda, a, x).

    local dt is a * (3 * tau * x - 2 + 2 * (lambda ^ 3) * x / y).
    local ddt is a * (3 * tau + 5 * x * dt + 2 * (1 - lambda ^ 2) * (lambda ^ 3) / (y ^ 3)).
    local dddt is a * (7 * x * ddt + 8 * dt - 6 * (1 - lambda ^ 2) * (lambda ^ 5) * x / (y ^ 5)).

    local delta is tau - t.
    return delta * (dt ^ 2 - delta * ddt / 2) / (dt * (dt ^ 2 - delta * ddt) + (dddt * delta ^ 2) / 6).
}

local function time_of_flight {
    parameter lambda, a, x.

    local sign is choose -1 if lambda < 0 else 1.

    if a > 0 {
        // Elliptical
        local alpha is 2 * trig:acos(x).
        local beta is 2 * trig:asin(sqrt(lambda ^ 2 / a)) * sign.
        return (a ^ 1.5 * ((alpha - trig:sin(alpha)) - (beta - trig:sin(beta)))) / 2.
    } else {
        // A hyperbolic trajectory is extremely unlikely to be the lowest
        // possible dV transfer however we calculate it anyway to be thorough.
        set a to -a.
        local alpha is 2 * trig:acosh(x).
        local beta is 2 * trig:asinh(sqrt(lambda ^ 2 / a)) * sign.
        return (a ^ 1.5 * ((beta - trig:sinh(beta)) - (alpha - trig:sinh(alpha)))) / 2.
    }
}