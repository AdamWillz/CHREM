This line is control log
* Building
Zone control description line
#NUM_FUNCTIONS number of functions
3
#
#
#FUNCTION_DATA
#
#
#CTL_TAG - THIS IS A MASTER OR DISTRIBUTED CONTROLLER FOR ZONE 1
* Control function
#SENSOR_DATA four values - zero for in zone, first digit is zone num if sense in one zone only
1 0 0 0
#ACTUATOR_DATA three values - zero for in zone
1 0 0
#NUM_YEAR_PERIODS number of periods in year
5 # To represent the seasonal use of the thermostat for heating and cooling
#
#VALID_DAYS day # to day #; THIS IS WINTER HEATING
1 91
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, law (basic control), start @ hr
0 1 0
#NUM_DATA_ITEMS Number of data items
7
#DATA_LINE1 space seperated
4128 0 0 0 21 100 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?
#
#VALID_DAYS day # to day #; THIS IS SPRING WITH BOTH HEAT AND COOL
92 154
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, law (basic control), start @ hr
0 1 0
#NUM_DATA_ITEMS Number of data items
7
#DATA_LINE1 space seperated
4128 0 0 0 21 25 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?
#
#VALID_DAYS day # to day #; THIS IS SUMMER COOLING
155 259
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, law (basic control), start @ hr
0 1 0
#NUM_DATA_ITEMS Number of data items
7
#DATA_LINE1 space seperated
4128 0 0 0 0 25 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?
#
#VALID_DAYS day # to day #; THIS IS FALL WITH BOTH HEAT AND COOL
260 280
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, law (basic control), start @ hr
0 1 0
#NUM_DATA_ITEMS Number of data items
7
#DATA_LINE1 space seperated
4128 0 0 0 21 25 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?
#
#VALID_DAYS day # to day #; THIS IS WINTER HEATING
281 365
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, law (basic control), start @ hr
0 1 0
#NUM_DATA_ITEMS Number of data items
7
#DATA_LINE1 space seperated
4128 0 0 0 21 100 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?
#
#
#CTL_TAG - THIS IS THE SLAVE CONTROLLER FOR ZONE NUMBER 2
* Control function
#SENSOR_DATA four values - master controller zone number followed by zeroes
1 0 0 0
#ACTUATOR_DATA three values - actuator zone number followed by zeroes
2 0 0
#NUM_YEAR_PERIODS number of periods in year
1
#
#VALID_DAYS day # to day #
1 365
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, law (SLAVE), start @ hr
0 21 0
#NUM_DATA_ITEMS Number of data items
3
#DATA_LINE1 space seperated: master controller number, heat capacity (W), cool capacity (W)
1 3872 0
#
#
#CTL_TAG - THIS IS A FREE-FLOAT CONTROLLER
* Control function
#SENSOR_DATA four values - zero for in present zone followed by zeroes
0 0 0 0
#ACTUATOR_DATA three values - zero for in present zone followed by zeroes
0 0 0
#NUM_YEAR_PERIODS number of periods in year
1
#
#VALID_DAYS day # to day #
1 365
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, law (FREE FLOATING), start @ hr
0 2 0
#NUM_DATA_ITEMS Number of data items
0
#END_FUNCTION_DATA
#
#
#ZONE_LINKS, each zone (in order) and list the loop number the zone corresponds too (e.g main = 1, if none the equal 0 [bad idea])
1 2 3
#
#END_CFC_FUNCTIONS_DATA
#
#END_PLANT_FUNCTIONS_DATA
#
* Mass Flow 
no flow control description supplied 
#NUM_AFN_FUNCTIONS number of afn functions 
3 
#
#AFN_TAG - THIS IS A MULTI-SENSOR CONTROLLER
* Control mass    1
# senses dry bulb temperature in main_1
1 0 0 0
# actuates flow component: main_1-ft_wd
-4  2  1
#NUM_YEAR_PERIODS number of periods in year
1
#
#VALID_DAYS day # to day #
1 365
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, (dry bulb > flow), law (AIM-2 Window Control Port), starting @
1 7 0
#NUM_DATA_ITEMS Number of data items
5.
#AFN_CTL_INPUTS, cooling_sensor_zone (zone for central cooling check) hot_setpoint (above this zone temp windows can operate) cold_setpoint(below this zone temp the windows are closed) DeltaT (if zone - ambient > deltaT windows can operate) minimum_ambient_temp (the minimum ambient temp which allows windows to open so as to prevent very cold air)
  1.0000 25.0000 21.0000 1.0000 21.0000
main_1-ft_wd   main_1    main_1-ft_wd
#
#AFN_TAG - THIS IS A MULTI-SENSOR CONTROLLER
* Control mass    2
# senses dry bulb temperature in main_1
1 0 0 0
# actuates flow component: main_1-bk_wd
-4  3  1
#NUM_YEAR_PERIODS number of periods in year
1
#
#VALID_DAYS day # to day #
1 365
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, (dry bulb > flow), law (AIM-2 Window Control Port), starting @
1 7 0
#NUM_DATA_ITEMS Number of data items
5.
#AFN_CTL_INPUTS, cooling_sensor_zone (zone for central cooling check) hot_setpoint (above this zone temp windows can operate) cold_setpoint(below this zone temp the windows are closed) DeltaT (if zone - ambient > deltaT windows can operate) minimum_ambient_temp (the minimum ambient temp which allows windows to open so as to prevent very cold air)
  1.0000 25.0000 21.0000 1.0000 21.0000
main_1-bk_wd   main_1    main_1-bk_wd
#
#AFN_TAG - THIS IS A MULTI-SENSOR CONTROLLER
* Control mass    3
# senses dry bulb temperature in main_1
1 0 0 0
# actuates flow component: main_1-lt_wd
-4  4  1
#NUM_YEAR_PERIODS number of periods in year
1
#
#VALID_DAYS day # to day #
1 365
#NUM_DAY_PERIODS
1
#CTL_TYPE ctl type, (dry bulb > flow), law (AIM-2 Window Control Port), starting @
1 7 0
#NUM_DATA_ITEMS Number of data items
5.
#AFN_CTL_INPUTS, cooling_sensor_zone (zone for central cooling check) hot_setpoint (above this zone temp windows can operate) cold_setpoint(below this zone temp the windows are closed) DeltaT (if zone - ambient > deltaT windows can operate) minimum_ambient_temp (the minimum ambient temp which allows windows to open so as to prevent very cold air)
  1.0000 25.0000 21.0000 1.0000 21.0000
main_1-lt_wd   main_1    main_1-lt_wd
#END_AFN_FUNCTIONS_DATA