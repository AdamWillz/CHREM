# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN main_2 This file describes the main_2
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
32 14 135
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   4.73 # base v1; total v1
 11.80   0.00   4.73 # base v2; total v2
 11.80   7.87   4.73 # base v3; total v3
  0.00   7.87   4.73 # base v4; total v4
  0.00   0.00   7.02 # top v1; total v5
 11.80   0.00   7.02 # top v2; total v6
 11.80   7.87   7.02 # top v3; total v7
  0.00   7.87   7.02 # top v4; total v8
  4.47   0.00   5.56 # front-wndw v1; total v9
  6.61   0.00   5.56 # front-wndw v2; total v10
  7.33   0.00   5.56 # front-wndw v3; total v11
  7.33   0.00   6.19 # front-wndw v4; total v12
  6.61   0.00   6.19 # front-wndw v5; total v13
  4.47   0.00   6.19 # front-wndw v6; total v14
 11.80   3.34   5.68 # right-wndw v1; total v15
 11.80   4.23   5.68 # right-wndw v2; total v16
 11.80   4.53   5.68 # right-wndw v3; total v17
 11.80   4.53   6.07 # right-wndw v4; total v18
 11.80   4.23   6.07 # right-wndw v5; total v19
 11.80   3.34   6.07 # right-wndw v6; total v20
  7.91   7.87   5.44 # back-wndw v1; total v21
  4.89   7.87   5.44 # back-wndw v2; total v22
  3.89   7.87   5.44 # back-wndw v3; total v23
  3.89   7.87   6.31 # back-wndw v4; total v24
  4.89   7.87   6.31 # back-wndw v5; total v25
  7.91   7.87   6.31 # back-wndw v6; total v26
  0.00   5.96   5.20 # left-wndw v1; total v27
  0.00   2.92   5.20 # left-wndw v2; total v28
  0.00   1.91   5.20 # left-wndw v3; total v29
  0.00   1.91   6.55 # left-wndw v4; total v30
  0.00   2.92   6.55 # left-wndw v5; total v31
  0.00   5.96   6.55 # left-wndw v6; total v32
#END_VERTICES
#SURFACES: line per surface- number of vertices followed by list of associated vert
# CCW fashion looking from outside toward inside
# return vertex is implied (i.e. 4 1 2 6 5 instead of 5 1 2 6 5 1)
4 1 4 3 2 # floor
4 5 6 7 8 # ceiling
16 1 2 6 5 1 9 14 13 10 9 1 10 13 12 11 10 # front
4 9 10 13 14 # front-aper
4 10 11 12 13 # front-frame
16 2 3 7 6 2 15 20 19 16 15 2 16 19 18 17 16 # right
4 15 16 19 20 # right-aper
4 16 17 18 19 # right-frame
16 3 4 8 7 3 21 26 25 22 21 3 22 25 24 23 22 # back
4 21 22 25 26 # back-aper
4 22 23 24 25 # back-frame
16 4 1 5 8 4 27 32 31 28 27 4 28 31 30 29 28 # left
4 27 28 31 32 # left-aper
4 28 29 30 31 # left-frame
#END_SURFACES
#UNUSED_INDEX: equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0 0 0
#SURFACE_INDENTATION (m): equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0 0 0
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
  1, floor         OPAQ  FLOR  M->M         ANOTHER        
  2, ceiling       OPAQ  CEIL  M->A_or_R    ANOTHER        
  3, front         OPAQ  VERT  M_wall       EXTERIOR       
  4, front-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  5, front-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
  6, right         OPAQ  VERT  M_wall       EXTERIOR       
  7, right-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  8, right-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
  9, back          OPAQ  VERT  M_wall       EXTERIOR       
 10, back-aper     TRAN  VERT  WNDW_200     EXTERIOR       
 11, back-frame    OPAQ  VERT  FRM_wood     EXTERIOR       
 12, left          OPAQ  VERT  M_wall       EXTERIOR       
 13, left-aper     TRAN  VERT  WNDW_200     EXTERIOR       
 14, left-frame    OPAQ  VERT  FRM_wood     EXTERIOR       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 0 0 0 0 0 92.9 0
