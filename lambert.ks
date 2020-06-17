@lazyglobal off.

// This code is a Kerboscript port of the PyKep project Lambert's problem solver,
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
// * Time of flight is always calculated using Lancaster's formula
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
// * The time of flight function uses some already calculated variables from the
//   householder function. Variable names and the signs of some formulas are
//   changed to match.
//
// Parameters:
// r1 [Vector] Position of the origin planet at departure time
// r2 [Vector] Position of the destination planet at arrival time
// tof [Scalar] Time of flight (arrival time minus departure time)
// mu [Scalar] Standard gravitational parameter
// flip_direction [Boolean] Change transfer direction between prograde/retrograde
global function lambert {
    parameter r1, r2, tof, mu, flip_direction.

    // Calculate "lambda" and normalized time of flight "t"
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

    // Change transfer direction between prograde/retrograde.
    if flip_direction {
        set it1 to -it1.
        set it2 to -it2.
        set lambda to -lambda.
    }

    // Determine Lancaster-Blanchard variable "x".
    local x is iterative_root_finder(lambda, t).

    // Construct velocity vectors from "x"
    local y is sqrt(1 - lambda ^ 2 * (1 - x ^ 2)).
    local z is lambda * y.
    local rho is (m1 - m2) / c.
    local gamma is sqrt(mu * s / 2).

    local vr1 is (z - x) - rho * (x + z).
    local vr2 is (x - z) - rho * (x + z).
    local vt is sqrt(1 - rho ^ 2) * (y + lambda * x).

    local v1 is (gamma / m1) * (vr1 * ir1 + vt * it1).
    local v2 is (gamma / m2) * (vr2 * ir2 + vt * it2).
    return lexicon("v1", v1, "v2", v2).
}

// Helper function to run iterative root finding algorithms.
local function iterative_root_finder {
    parameter lambda, t.

    local x is initial_guess(lambda, t).
    local delta is 1.
    local iterations is 0.

    until abs(delta) < 0.00001 or iterations = 15 {
        set delta to householders_method(lambda, t, x).
        set x to x - delta.
        set iterations to iterations + 1.
    }

    return x.
}

// The formulas for the initial guess of "x" are so accurate that on average
// only 2 to 3 iterations of Householder's method are needed to converge.
local function initial_guess {
    parameter lambda, t.

    local t0 is constant:degtorad * arccos(lambda) + lambda * sqrt(1 - lambda ^ 2).
    local t1 is (2 / 3) * (1 - lambda ^ 3).

    if t >= t0 {
        return (t0 / t) ^ (2 / 3) - 1.
    } else if t <= t1 {
        return (5 * t1 * (t1 - t)) / (2 * t * (1 - lambda ^ 5)) + 1.
    } else {
        return (t0 / t) ^ (ln(t1 / t0) / ln(2)) - 1.
    }
}

// 3rd order Householder's method. For some context the method of order 1 is the
// well known Newton's method and the method of order 2 is Halley's method.
local function householders_method {
    parameter lambda, t, x.

    local a is 1 - x ^ 2.
    local y is sqrt(1 - lambda ^ 2 * a).
    local tau is time_of_flight(lambda, a, x, y).
    local delta is tau - t.

    local dt is (3 * tau * x - 2 + 2 * (lambda ^ 3) * x / y) / a.
    local ddt is (3 * tau + 5 * x * dt + 2 * (1 - lambda ^ 2) * (lambda ^ 3) / (y ^ 3)) / a.
    local dddt is (7 * x * ddt + 8 * dt - 6 * (1 - lambda ^ 2) * (lambda ^ 5) * x / (y ^ 5)) / a.

    return delta * (dt ^ 2 - delta * ddt / 2) / (dt * (dt ^ 2 - delta * ddt) + (dddt * delta ^ 2) / 6).
}

// Calculate the time of flight using Lancaster's formula.
local function time_of_flight {
    parameter lambda, a, x, y.

    local b is sqrt(abs(a)).
    local c is lambda * a + x * y.
    local psi is choose constant:degtorad * arccos(c) if a > 0 else ln(c + b * (y - lambda * x)).

    return (psi / b - x + lambda * y) / a.
}