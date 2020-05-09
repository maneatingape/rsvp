runoncepath("lambert.ks").
runoncepath("kepler.ks").

//test1().
//test2().
//test3().
//test4().

local count is 0.
local start is time:seconds.

local t1 is kerbinTimeToSeconds(1, 236, 4, 19, 12).
local t2 is kerbinTimeToSeconds(2, 69, 2, 36, 0).
local tof is t2 - t1.
local osv1 is orbitalStateVectors(kerbin, t1).
local osv2 is orbitalStateVectors(duna, t2).

until count = 1000 {
	local solution is lambert(osv1:position, osv2:position, tof, sun:mu, false).
	set count to count + 1.
}
print count + " iteration, took " + (time:seconds - start) + " seconds".




local function test1 {
	local t1 is kerbinTimeToSeconds(1, 236, 4, 19, 12).
	local t2 is kerbinTimeToSeconds(2, 69, 2, 36, 0).
	transferDetails(sun, kerbin, t1, duna, t2).
}

local function test2 {
	local t1 is kerbinTimeToSeconds(2, 256, 3, 36, 0).
	local t2 is kerbinTimeToSeconds(7, 19, 5, 31, 12).
	transferDetails(sun, kerbin, t1, eeloo, t2, true).
}

local function test3 {
	local t1 is kerbinTimeToSeconds(1, 269, 1, 12, 0).
	local t2 is kerbinTimeToSeconds(1, 405, 2, 327, 36).
	transferDetails(sun, kerbin, t1, moho, t2, false).
}

local function test4 {
	local t1 is kerbinTimeToSeconds(1, 3, 3, 36, 0).
	local t2 is kerbinTimeToSeconds(1, 6, 1, 38, 31).
	transferDetails(jool, laythe, t1, tylo, t2, true).
}


local function transferDetails {
	parameter focalBody, fromBody, t1, toBody, t2, retrograde is false.

	local solution is transferDeltaV(focalBody, fromBody, t1, toBody, t2, retrograde).
	local ejection is ejectionDeltaV(fromBody, 100000, solution:dv1).
	local insertion is insertionDeltaV(toBody, 100000, solution:dv2).

	print "-----------------------------".
	print fromBody:name + " => " + toBody:name.
	print "Ejection: " + ejection.
	print "Insertion: " + insertion.
	print "Total: " + (ejection + insertion).	
}

local function transferDeltaV {
	parameter focalBody, fromBody, t1, toBody, t2, retrograde.

	local osv1 is orbitalStateVectors(fromBody, t1).
	local osv2 is orbitalStateVectors(toBody, t2).
	local tof is t2 - t1.
	local solution is lambert(osv1:position, osv2:position, tof, focalBody:mu, retrograde).

	return lexicon("dv1", solution:v1 - osv1:velocity, "dv2", osv2:velocity - solution:v2).
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