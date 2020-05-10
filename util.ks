@lazyglobal off.

global trig is lexicon(
	// Regular trig functions using radians instead of degrees
	"sin", {
		parameter x.
		return sin(constant:radtodeg * x).
	},
	"cos", {
		parameter x.
		return cos(constant:radtodeg * x).
	},	
	"asin", {
		parameter x.
		return constant:degtorad * arcsin(x).
	},
	"acos", {
		parameter x.
		return constant:degtorad * arccos(x).
	},
	// Hyperbolic variants
	"sinh", {
		parameter x.
		return (constant:e ^ x - constant:e ^ (-x)) / 2.
	},
	"cosh", {
		parameter x.
		return (constant:e ^ x + constant:e ^ (-x)) / 2.
	},
	"asinh", {
		parameter x.
		return ln(x + sqrt(x ^ 2 + 1)).
	},
	"acosh", {
		parameter x.
		return ln(x + sqrt(x ^ 2 - 1)).
	}
).

global function iterative_root_finder {
	parameter x0, f, epsilon, max_iterations.

	local x is x0.
	local delta is abs(epsilon) + 1.
	local iterations is 0.

	until abs(delta) < epsilon or iterations = max_iterations {
        set delta to f(x).
        set x to x - delta.
        set iterations to iterations + 1.
    }

    return x.
}