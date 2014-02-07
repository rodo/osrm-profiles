osrm-profiles
=============

Lua profiles for [OSRM](https://github.com/DennisOSRM/Project-OSRM/wiki)
The files were developped to work with the version 0.3.7 of OSRM.

How to use them
===============

Copy or link the _lua_ files to the _profiles_ directory of your osrm
installation.

Files
=====

All the following files derived from _car.lua_ distributed with OSRM.

* car_hazmat.lua for vehicle with hazardous matarials inboard

* truck.lua for trucks with weight > 3.5t and height >= 4.0 meters

* truck_hazmat.lua for trucks with weight > 3.5t and height >= 4.0
  meters with hazardous materials inboard.

TODO
====

Use all variants of hazmat like access tag does

Licence
=======

These files are licensed under GPLv3

Author
======

Rodolphe Quiédeville <rodolphe@quiedeville.org>