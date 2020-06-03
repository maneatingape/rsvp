runoncepath("kos-launch-window-finder/lambert.ks").

test1().
test2().
test3().
test4().

//local departureOffset is 0.
//local timeOfFlight is tofInitialGuess(sun, kerbin, duna).
//local stepSize is kerbinTimeToSeconds(0, 8, 0, 0, 0).
//local threshold is kerbinTimeToSeconds(0, 1, 0, 0, 0).

//local t1 is departureOffset. //+time:seconds.
//local t2 is departureOffset + timeOfFlight.
//local retrogradeFlag is determineDirection(sun, kerbin, t1, duna, t2).


//until stepSize < threshold {

//}



local function test1 {
	local t1 is kerbinTimeToSeconds(1, 236, 4, 19, 12).
	local t2 is kerbinTimeToSeconds(2, 69, 2, 36, 0).
	transferDetails(sun, kerbin, t1, duna, t2, false).
}

local function test2 {
	local t1 is kerbinTimeToSeconds(2, 256, 3, 36, 0).
	local t2 is kerbinTimeToSeconds(7, 19, 5, 31, 12).
	transferDetails(sun, kerbin, t1, eeloo, t2, true).
}

local function test3 {
	local t1 is kerbinTimeToSeconds(1, 269, 1, 12, 0).
	local t2 is kerbinTimeToSeconds(1, 405, 2, 327, 36).
	transferDetails(sun, kerbin, t1, moho, t2, true).
}

local function test4 {
	local t1 is kerbinTimeToSeconds(1, 3, 3, 36, 0).
	local t2 is kerbinTimeToSeconds(1, 6, 1, 38, 31).
	transferDetails(jool, laythe, t1, tylo, t2, false).
}

local function tofInitialGuess {
	parameter focalBody, fromBody, toBody.

	// Return the time of half a Hohmann transfer between the two bodies
	local a is (fromBody:orbit:semimajoraxis + toBody:orbit:semimajoraxis) / 2.
	return constant:pi * sqrt(a ^ 3 / focalBody:mu).
}

local function determineDirection {
	parameter focalBody, fromBody, t1, toBody, t2, flip_direction.

	local progradeDeltaV is totalDeltaV(sun, kerbin, t1, duna, t2, false).
	local retrogradeDeltaV is totalDeltaV(sun, kerbin, t1, duna, t2, true).
	return retrogradeDeltaV < progradeDeltaV.
}

local function transferDetails {
	parameter focalBody, fromBody, t1, toBody, t2, flip_direction.

	local solution is transferDeltaV(focalBody, fromBody, t1, toBody, t2, flip_direction).
	local ejection is ejectionDeltaV(fromBody, 100000, solution:dv1).
	local insertion is insertionDeltaV(toBody, 100000, solution:dv2).

	print "-----------------------------".
	print fromBody:name + " => " + toBody:name.
	print "Ejection: " + ejection.
	print "Insertion: " + insertion.
	print "Total: " + (ejection + insertion).
}

local function totalDeltaV {
	parameter focalBody, fromBody, t1, toBody, t2, flip_direction.

	local solution is transferDeltaV(focalBody, fromBody, t1, toBody, t2, flip_direction).
	local ejection is ejectionDeltaV(fromBody, 100000, solution:dv1).
	local insertion is insertionDeltaV(toBody, 100000, solution:dv2).

	return ejection + insertion.
}

local function transferDeltaV {
	parameter focalBody, fromBody, t1, toBody, t2, flip_direction.

	local r1 is positionat(fromBody, t1) - focalBody:position.
	local r2 is positionat(toBody, t2) - focalBody:position.
	local solution is lambert(r1, r2, t2 - t1, focalBody:mu, flip_direction).

	local v1 is velocityat(fromBody, t1):orbit.
	local v2 is velocityat(toBody, t2):orbit.
	return lexicon("dv1", solution:v1 - v1, "dv2", v2 - solution:v2).
}

function ejectionDeltaV {
	parameter body, altitude, dv1.

	local r1 is body:radius + altitude.
	local r2 is body:soiradius.

	local mu is body:mu.
	local v1 is sqrt(mu / r1).
	local v2 is dv1:mag.

	local theta is vang(dv1, v(dv1:x, 0, dv1:z)).
	local escapeV is sqrt(v2 ^ 2 - 2 * mu * (r1 - r2) / (r1 * r2)).

	return sqrt(escapeV ^ 2 + v1 ^ 2 - 2 * escapeV * v1 * cos(theta)).
}

function insertionDeltaV {
	parameter body, altitude, dv2.

	local r1 is body:radius + altitude.
	local r2 is body:soiradius.

	local mu is body:mu.
	local v1 is sqrt(mu / r1).
	local v2 is dv2:mag.

	return sqrt(v2 ^ 2 - 2 * mu * (r1 - r2) / (r1 * r2)) - v1.
}

function kerbinTimeToSeconds {
	parameter years, days, hours, minutes, seconds.

	local _minutes is 60.
	local _hours is 60 * _minutes.
	local _days is 6 * _hours.
	local _years is 426 * _days.

	return _years * (years - 1) + _days * (days - 1) + _hours * hours + _minutes * minutes + seconds.
}