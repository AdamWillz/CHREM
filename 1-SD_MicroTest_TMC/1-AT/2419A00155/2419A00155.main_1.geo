# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN main_1 This file describes the main_1
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
26 12 135
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   2.29 # base v1; total v1
  7.40   0.00   2.29 # base v2; total v2
 11.52   0.00   2.29 # base v3; total v3
 11.52   7.69   2.29 # base v4; total v4
  7.40   7.69   2.29 # base v5; total v5
  0.00   7.69   2.29 # base v6; total v6
  0.00   0.00   4.73 # top v1; total v7
 11.52   0.00   4.73 # top v2; total v8
 11.52   7.69   4.73 # top v3; total v9
  0.00   7.69   4.73 # top v4; total v10
  2.21   0.00   2.71 # front-wndw v1; total v11
  6.93   0.00   2.71 # front-wndw v2; total v12
  8.50   0.00   2.71 # front-wndw v3; total v13
  8.50   0.00   4.31 # front-wndw v4; total v14
  6.93   0.00   4.31 # front-wndw v5; total v15
  2.21   0.00   4.31 # front-wndw v6; total v16
 10.61   0.00   2.39 # front-door v1; total v17
 11.42   0.00   2.39 # front-door v2; total v18
 11.42   0.00   4.42 # front-door v3; total v19
 10.61   0.00   4.42 # front-door v4; total v20
  9.02   7.69   2.74 # back-wndw v1; total v21
  4.13   7.69   2.74 # back-wndw v2; total v22
  2.50   7.69   2.74 # back-wndw v3; total v23
  2.50   7.69   4.28 # back-wndw v4; total v24
  4.13   7.69   4.28 # back-wndw v5; total v25
  9.02   7.69   4.28 # back-wndw v6; total v26
#END_VERTICES
#SURFACES: line per surface- number of vertices followed by list of associated vert
# CCW fashion looking from outside toward inside
# return vertex is implied (i.e. 4 1 2 6 5 instead of 5 1 2 6 5 1)
4 1 6 5 2 # floor
4 2 5 4 3 # floor-exposed
4 7 8 9 10 # ceiling
23 1 2 3 8 7 1 11 16 15 12 11 1 12 15 14 13 12 1 17 20 19 18 17 # front
4 11 12 15 16 # front-aper
4 12 13 14 15 # front-frame
4 17 18 19 20 # front-door
4 3 4 9 8 # right
17 4 5 6 10 9 4 21 26 25 22 21 4 22 25 24 23 22 # back
4 21 22 25 26 # back-aper
4 22 23 24 25 # back-frame
4 6 1 7 10 # left
#END_SURFACES
#UNUSED_INDEX: equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0
#SURFACE_INDENTATION (m): equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0
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
  1, floor         OPAQ  FLOR  M->B         ANOTHER        
  2, floor-exposed OPAQ  FLOR  M_floor_exp  EXTERIOR       
  3, ceiling       OPAQ  CEIL  M->A_or_R    ANOTHER        
  4, front         OPAQ  VERT  M_wall       EXTERIOR       
  5, front-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  6, front-frame   OPAQ  VERT  FRM_wood     EXTERIOR       
  7, front-door    OPAQ  VERT  D_mtl_Plur   EXTERIOR       
  8, right         OPAQ  VERT  M_wall       EXTERIOR       
  9, back          OPAQ  VERT  M_wall       EXTERIOR       
 10, back-aper     TRAN  VERT  WNDW_200     EXTERIOR       
 11, back-frame    OPAQ  VERT  FRM_Al       EXTERIOR       
 12, left          OPAQ  VERT  M_wall       EXTERIOR       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 2 0 0 0 0 88.6 0
