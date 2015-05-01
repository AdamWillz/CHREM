# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN main_2 This file describes the main_2
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
26 12 270
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   4.76 # base v1; total v1
  7.76   0.00   4.76 # base v2; total v2
  7.76   9.89   4.76 # base v3; total v3
  0.00   9.89   4.76 # base v4; total v4
  0.00   0.00   5.73 # top v1; total v5
  7.76   0.00   5.73 # top v2; total v6
  7.76   9.89   5.73 # top v3; total v7
  0.00   9.89   5.73 # top v4; total v8
  2.44   0.00   5.01 # front-wndw v1; total v9
  4.60   0.00   5.01 # front-wndw v2; total v10
  5.32   0.00   5.01 # front-wndw v3; total v11
  5.32   0.00   5.48 # front-wndw v4; total v12
  4.60   0.00   5.48 # front-wndw v5; total v13
  2.44   0.00   5.48 # front-wndw v6; total v14
  7.76   3.94   5.12 # right-wndw v1; total v15
  7.76   5.45   5.12 # right-wndw v2; total v16
  7.76   5.95   5.12 # right-wndw v3; total v17
  7.76   5.95   5.37 # right-wndw v4; total v18
  7.76   5.45   5.37 # right-wndw v5; total v19
  7.76   3.94   5.37 # right-wndw v6; total v20
  5.55   9.89   4.97 # back-wndw v1; total v21
  3.05   9.89   4.97 # back-wndw v2; total v22
  2.21   9.89   4.97 # back-wndw v3; total v23
  2.21   9.89   5.52 # back-wndw v4; total v24
  3.05   9.89   5.52 # back-wndw v5; total v25
  5.55   9.89   5.52 # back-wndw v6; total v26
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
4 4 1 5 8 # left
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
  1, floor         OPAQ  FLOR  M->M         ANOTHER        
  2, ceiling       OPAQ  CEIL  M->A_or_R    ANOTHER        
  3, front         OPAQ  VERT  M_wall       EXTERIOR       
  4, front-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  5, front-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
  6, right         OPAQ  VERT  M_wall       EXTERIOR       
  7, right-aper    TRAN  VERT  WNDW_234     EXTERIOR       
  8, right-frame   OPAQ  VERT  FRM_Vnl      EXTERIOR       
  9, back          OPAQ  VERT  M_wall       EXTERIOR       
 10, back-aper     TRAN  VERT  WNDW_234     EXTERIOR       
 11, back-frame    OPAQ  VERT  FRM_Vnl      EXTERIOR       
 12, left          OPAQ  VERT  M_wall       EXTERIOR       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 0 0 0 0 0 76.7 0
