# Description

[Launch Window](https://en.wikipedia.org/wiki/Launch_window) finder for the game [Kerbal Space Program](https://www.kerbalspaceprogram.com/) written for the [kOS](https://ksp-kos.github.io/KOS/) mod in the KerboScript language.

These scripts allow a player to find the lowest delta-v transfer between two planets in-game, either directly from the kOS console or from their own scripts.

Think of it as in-game alternative to the excellent web based [Launch Window Planner](https://alexmoon.github.io/ksp/) by Alex Moon.


## Technical Details

The functionality is built around a [Lambert's problem](https://en.wikipedia.org/wiki/Lambert%27s_problem) solver. Given the position of two planets and a duration, this calculates the delta-v required for a transfer orbit between the two positions that will take exactly that duration.

The Lambert solver code is a kOS port of the [PyKep project](https://github.com/esa/pykep) developed by the European Space Agency. The algorithm and equations are described in excellent detail in the paper [Revisiting Lambert’s problem](https://www.esa.int/gsp/ACT/doc/MAD/pub/ACT-RPR-MAD-2014-RevisitingLambertProblem.pdf) by Dario Izzio.

The original code is extremly robust and flexible. For the KSP universe this is overkill, so some simplifications have been made, in particular multi-revolution transfer orbits are not considered.