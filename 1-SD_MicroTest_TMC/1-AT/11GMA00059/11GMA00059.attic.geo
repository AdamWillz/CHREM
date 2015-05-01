# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN attic This file describes the attic
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
8 6 270
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   5.73 # base v1; total v1
  7.76   0.00   5.73 # base v2; total v2
  7.76   9.89   5.73 # base v3; total v3
  0.00   9.89   5.73 # base v4; total v4
  0.00   4.90   7.35 # top v1; total v5
  7.76   4.90   7.35 # top v2; total v6
  7.76   5.00   7.35 # top v3; total v7
  0.00   5.00   7.35 # top v4; total v8
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
  1, floor         OPAQ  FLOR  A_or_R->M    ANOTHER        
  2, ceiling       OPAQ  CEIL  A_or_R_slop  EXTERIOR       
  3, front         OPAQ  SLOP  A_or_R_slop  EXTERIOR       
  4, right         OPAQ  VERT  A_or_R_gbl   EXTERIOR       
  5, back          OPAQ  SLOP  A_or_R_slop  EXTERIOR       
  6, left          OPAQ  VERT  A_or_R_gbl   EXTERIOR       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 0 0 0 0 0 76.7 0
