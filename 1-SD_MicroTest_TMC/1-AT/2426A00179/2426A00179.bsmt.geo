# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN bsmt This file describes the bsmt
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
8 6 135
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   0.00 # base v1; total v1
  7.08   0.00   0.00 # base v2; total v2
  7.08   7.87   0.00 # base v3; total v3
  0.00   7.87   0.00 # base v4; total v4
  0.00   0.00   2.29 # top v1; total v5
  7.08   0.00   2.29 # top v2; total v6
  7.08   7.87   2.29 # top v3; total v7
  0.00   7.87   2.29 # top v4; total v8
#END_VERTICES
#SURFACES: line per surface- number of vertices followed by list of associated vert
# CCW fashion looking from outside toward inside
# return vertex is implied (i.e. 4 1 2 6 5 instead of 5 1 2 6 5 1)
4 1 4 3 2 # floor
4 5 6 7 8 # ceiling
4 1 2 6 5 # front
4 2 3 7 6 # right
4 3 4 8 7 # back
4 4 1 5 8 # left
#END_SURFACES
#UNUSED_INDEX: equal to number of surfaces
0 0 0 0 0 0
#SURFACE_INDENTATION (m): equal to number of surfaces
0 0 0 0 0 0
#INSOLATION
3 0 0 0 # default insolation distribution
#SURFACE_ATTRIBUTES: must be columner format with line for each surface (see exemplar for example)
# surface attributes follow: 
# id number
# surface name
# construction type OPAQ, TRAN, CFC
# placement FLOR, CEIL, VERT, SLOP
# construction name
# outside condition EXTERIOR, ANOTHER, BASESIMP, ADIABATIC
  1, floor         OPAQ  FLOR  B_sl_cc      BASESIMP       
  2, ceiling       OPAQ  CEIL  B->M         ANOTHER        
  3, front         OPAQ  VERT  B_wall_cc    BASESIMP       
  4, right         OPAQ  VERT  B_wall_cc    BASESIMP       
  5, back          OPAQ  VERT  B_wall_cc    BASESIMP       
  6, left          OPAQ  VERT  B_wall_cc    BASESIMP       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 0 0 0 0 0 55.7 0
