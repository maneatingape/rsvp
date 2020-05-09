runoncepath("util.ks").

global function orbitalStateVectors {
	parameter body, t.

	local a is body:orbit:semimajoraxis.
	local b is body:orbit:semiminoraxis.
	local e is body:orbit:eccentricity.

	local i is body:orbit:inclination.
	local omega is body:orbit:longitudeofascendingnode.
	local omicron is body:orbit:argumentofperiapsis.

	local mu is body:orbit:body:mu.
	local t0 is body:orbit:epoch.
	local m0 is body:orbit:meananomalyatepoch * constant:degtorad.

	local n is sqrt(mu / a ^ 3).
	local m is mod(m0 + n * (t - t0), 2 * constant:pi).

	local f is newtonsMethod@:bind(e, m).
	local ea is iterativeRootFinder(m, f, 1e-5, 15).

	local x is a * (trig:cos(ea) - e).
	local z is b * trig:sin(ea).

	local gamma is n / (1 - e * trig:cos(ea)).
	local dx is gamma * a * -trig:sin(ea).
	local dz is gamma * b * trig:cos(ea).

	local rotateToInertialFrame is r(0, -omega, 0) * r(-i, 0, 0) * r(0, -omicron, 0).
	local position is v(x, 0, z) * rotateToInertialFrame.
	local velocity is v(dx, 0, dz) * rotateToInertialFrame.

	return lexicon("position", position, "velocity", velocity).
}

global function rotateToUniverse {
	parameter osv.
	
	local rotation is rotatefromto(v(1, 0, 0), solarprimevector).
	local position is osv:position * rotation.
	local velocity is osv:velocity * rotation.

	return lexicon("position", position, "velocity", velocity).
}

local function newtonsMethod {
	parameter e, m, ea.

	return (m + e * trig:sin(ea) - ea) / (e * trig:cos(ea) - 1).
}