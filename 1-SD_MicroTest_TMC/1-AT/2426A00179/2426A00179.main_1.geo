# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN main_1 This file describes the main_1
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
42 17 135
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   2.29 # base v1; total v1
  7.08   0.00   2.29 # base v2; total v2
 11.80   0.00   2.29 # base v3; total v3
 11.80   7.87   2.29 # base v4; total v4
  7.08   7.87   2.29 # base v5; total v5
  0.00   7.87   2.29 # base v6; total v6
  0.00   0.00   4.73 # top v1; total v7
 11.80   0.00   4.73 # top v2; total v8
 11.80   7.87   4.73 # top v3; total v9
  0.00   7.87   4.73 # top v4; total v10
  4.16   0.00   3.18 # front-wndw v1; total v11
  6.16   0.00   3.18 # front-wndw v2; total v12
  6.83   0.00   3.18 # front-wndw v3; total v13
  6.83   0.00   3.84 # front-wndw v4; total v14
  6.16   0.00   3.84 # front-wndw v5; total v15
  4.16   0.00   3.84 # front-wndw v6; total v16
 10.89   0.00   2.39 # front-door v1; total v17
 11.70   0.00   2.39 # front-door v2; total v18
 11.70   0.00   4.42 # front-door v3; total v19
 10.89   0.00   4.42 # front-door v4; total v20
 11.80   3.00   3.30 # right-wndw v1; total v21
 11.80   3.80   3.30 # right-wndw v2; total v22
 11.80   4.06   3.30 # right-wndw v3; total v23
 11.80   4.06   3.72 # right-wndw v4; total v24
 11.80   3.80   3.72 # right-wndw v5; total v25
 11.80   3.00   3.72 # right-wndw v6; total v26
 11.80   6.96   2.39 # right-door v1; total v27
 11.80   7.77   2.39 # right-door v2; total v28
 11.80   7.77   4.42 # right-door v3; total v29
 11.80   6.96   4.42 # right-door v4; total v30
  7.92   7.87   3.04 # back-wndw v1; total v31
  4.89   7.87   3.04 # back-wndw v2; total v32
  3.88   7.87   3.04 # back-wndw v3; total v33
  3.88   7.87   3.98 # back-wndw v4; total v34
  4.89   7.87   3.98 # back-wndw v5; total v35
  7.92   7.87   3.98 # back-wndw v6; total v36
  0.00   5.97   2.79 # left-wndw v1; total v37
  0.00   2.92   2.79 # left-wndw v2; total v38
  0.00   1.90   2.79 # left-wndw v3; total v39
  0.00   1.90   4.23 # left-wndw v4; total v40
  0.00   2.92   4.23 # left-wndw v5; total v41
  0.00   5.97   4.23 # left-wndw v6; total v42
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
22 3 4 9 8 3 21 26 25 22 21 3 22 25 24 23 22 3 27 30 29 28 27 # right
4 21 22 25 26 # right-aper
4 22 23 24 25 # right-frame
4 27 28 29 30 # right-door
17 4 5 6 10 9 4 31 36 35 32 31 4 32 35 34 33 32 # back
4 31 32 35 36 # back-aper
4 32 33 34 35 # back-frame
16 6 1 7 10 6 37 42 41 38 37 6 38 41 40 39 38 # left
4 37 38 41 42 # left-aper
4 38 39 40 41 # left-frame
#END_SURFACES
#UNUSED_INDEX: equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#SURFACE_INDENTATION (m): equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
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
  3, ceiling       OPAQ  CEIL  M->M         ANOTHER        
  4, front         OPAQ  VERT  M_wall       EXTERIOR       
  5, front-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  6, front-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
  7, front-door    OPAQ  VERT  D_mtl_EPS    EXTERIOR       
  8, right         OPAQ  VERT  M_wall       EXTERIOR       
  9, right-aper    TRAN  VERT  WNDW_200     EXTERIOR       
 10, right-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
 11, right-door    OPAQ  VERT  D_mtl_EPS    EXTERIOR       
 12, back          OPAQ  VERT  M_wall       EXTERIOR       
 13, back-aper     TRAN  VERT  WNDW_200     EXTERIOR       
 14, back-frame    OPAQ  VERT  FRM_wood     EXTERIOR       
 15, left          OPAQ  VERT  M_wall       EXTERIOR       
 16, left-aper     TRAN  VERT  WNDW_200     EXTERIOR       
 17, left-frame    OPAQ  VERT  FRM_wood     EXTERIOR       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 2 0 0 0 0 92.9 0
