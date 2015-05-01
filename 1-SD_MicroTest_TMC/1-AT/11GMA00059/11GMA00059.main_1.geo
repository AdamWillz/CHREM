# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN main_1 This file describes the main_1
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
36 15 270
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   2.44 # base v1; total v1
  9.88   0.00   2.44 # base v2; total v2
  9.88   9.89   2.44 # base v3; total v3
  0.00   9.89   2.44 # base v4; total v4
  0.00   0.00   4.76 # top v1; total v5
  7.76   0.00   4.76 # top v2; total v6
  9.88   0.00   4.76 # top v3; total v7
  9.88   9.89   4.76 # top v4; total v8
  7.76   9.89   4.76 # top v5; total v9
  0.00   9.89   4.76 # top v6; total v10
  2.52   0.00   3.04 # front-wndw v1; total v11
  5.33   0.00   3.04 # front-wndw v2; total v12
  6.27   0.00   3.04 # front-wndw v3; total v13
  6.27   0.00   4.16 # front-wndw v4; total v14
  5.33   0.00   4.16 # front-wndw v5; total v15
  2.52   0.00   4.16 # front-wndw v6; total v16
  8.69   0.00   2.54 # front-door v1; total v17
  9.78   0.00   2.54 # front-door v2; total v18
  9.78   0.00   4.57 # front-door v3; total v19
  8.69   0.00   4.57 # front-door v4; total v20
  9.88   3.58   3.30 # right-wndw v1; total v21
  9.88   5.21   3.30 # right-wndw v2; total v22
  9.88   5.75   3.30 # right-wndw v3; total v23
  9.88   5.75   3.90 # right-wndw v4; total v24
  9.88   5.21   3.90 # right-wndw v5; total v25
  9.88   3.58   3.90 # right-wndw v6; total v26
  9.88   9.23   2.54 # right-door v1; total v27
  9.88   9.79   2.54 # right-door v2; total v28
  9.88   9.79   4.55 # right-door v3; total v29
  9.88   9.23   4.55 # right-door v4; total v30
  7.39   9.89   2.95 # back-wndw v1; total v31
  3.72   9.89   2.95 # back-wndw v2; total v32
  2.49   9.89   2.95 # back-wndw v3; total v33
  2.49   9.89   4.25 # back-wndw v4; total v34
  3.72   9.89   4.25 # back-wndw v5; total v35
  7.39   9.89   4.25 # back-wndw v6; total v36
#END_VERTICES
#SURFACES: line per surface- number of vertices followed by list of associated vert
# CCW fashion looking from outside toward inside
# return vertex is implied (i.e. 4 1 2 6 5 instead of 5 1 2 6 5 1)
4 1 4 3 2 # floor
4 5 6 9 10 # ceiling
4 6 7 8 9 # ceiling-exposed
23 1 2 7 6 5 1 11 16 15 12 11 1 12 15 14 13 12 1 17 20 19 18 17 # front
4 11 12 15 16 # front-aper
4 12 13 14 15 # front-frame
4 17 18 19 20 # front-door
22 2 3 8 7 2 21 26 25 22 21 2 22 25 24 23 22 2 27 30 29 28 27 # right
4 21 22 25 26 # right-aper
4 22 23 24 25 # right-frame
4 27 28 29 30 # right-door
17 3 4 10 9 8 3 31 36 35 32 31 3 32 35 34 33 32 # back
4 31 32 35 36 # back-aper
4 32 33 34 35 # back-frame
4 4 1 5 10 # left
#END_SURFACES
#UNUSED_INDEX: equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#SURFACE_INDENTATION (m): equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
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
  2, ceiling       OPAQ  CEIL  M->M         ANOTHER        
  3, ceiling-exposed OPAQ  CEIL  M_ceil_exp   EXTERIOR       
  4, front         OPAQ  VERT  M_wall       EXTERIOR       
  5, front-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  6, front-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
  7, front-door    OPAQ  VERT  D_mtl_EPS    EXTERIOR       
  8, right         OPAQ  VERT  M_wall       EXTERIOR       
  9, right-aper    TRAN  VERT  WNDW_234     EXTERIOR       
 10, right-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
 11, right-door    OPAQ  VERT  D_mtl_Plur   EXTERIOR       
 12, back          OPAQ  VERT  M_wall       EXTERIOR       
 13, back-aper     TRAN  VERT  WNDW_234     EXTERIOR       
 14, back-frame    OPAQ  VERT  FRM_Vnl      EXTERIOR       
 15, left          OPAQ  VERT  M_wall       EXTERIOR       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 0 0 0 0 0 97.7 0
