# geometry of main defined in: ./zone.geo
#ZONE_NAME: zone description type, zone name, description
GEN bsmt This file describes the bsmt
#VER_SUR_ROT: vertex count, surface count, rotation angle CCW looking down (degrees)
24 11 225
#VERTICES: X co-ord, Y co-ord, Z co-ord
# line per vertex- base in counter-clockwise (CCW) fashion looking down, then top in CCW fashion
# then additional vertices for windows/doors
  0.00   0.00   0.00 # base v1; total v1
 10.95   0.00   0.00 # base v2; total v2
 10.95   7.72   0.00 # base v3; total v3
  0.00   7.72   0.00 # base v4; total v4
  0.00   0.00   2.44 # top v1; total v5
 10.95   0.00   2.44 # top v2; total v6
 10.95   7.72   2.44 # top v3; total v7
  0.00   7.72   2.44 # top v4; total v8
  2.80   0.00   0.61 # front-wndw v1; total v9
  6.17   0.00   0.61 # front-wndw v2; total v10
  7.29   0.00   0.61 # front-wndw v3; total v11
  7.29   0.00   1.83 # front-wndw v4; total v12
  6.17   0.00   1.83 # front-wndw v5; total v13
  2.80   0.00   1.83 # front-wndw v6; total v14
  9.99   0.00   0.10 # front-door v1; total v15
 10.85   0.00   0.10 # front-door v2; total v16
 10.85   0.00   2.13 # front-door v3; total v17
  9.99   0.00   2.13 # front-door v4; total v18
 10.95   3.44   1.07 # right-wndw v1; total v19
 10.95   4.07   1.07 # right-wndw v2; total v20
 10.95   4.28   1.07 # right-wndw v3; total v21
 10.95   4.28   1.37 # right-wndw v4; total v22
 10.95   4.07   1.37 # right-wndw v5; total v23
 10.95   3.44   1.37 # right-wndw v6; total v24
#END_VERTICES
#SURFACES: line per surface- number of vertices followed by list of associated vert
# CCW fashion looking from outside toward inside
# return vertex is implied (i.e. 4 1 2 6 5 instead of 5 1 2 6 5 1)
4 1 4 3 2 # floor
4 5 6 7 8 # ceiling
22 1 2 6 5 1 9 14 13 10 9 1 10 13 12 11 10 1 15 18 17 16 15 # front
4 9 10 13 14 # front-aper
4 10 11 12 13 # front-frame
4 15 16 17 18 # front-door
16 2 3 7 6 2 19 24 23 20 19 2 20 23 22 21 20 # right
4 19 20 23 24 # right-aper
4 20 21 22 23 # right-frame
4 3 4 8 7 # back
4 4 1 5 8 # left
#END_SURFACES
#UNUSED_INDEX: equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0
#SURFACE_INDENTATION (m): equal to number of surfaces
0 0 0 0 0 0 0 0 0 0 0
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
  3, front         OPAQ  VERT  B_wall_pony  EXTERIOR       
  4, front-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  5, front-frame   OPAQ  VERT  FRM_wood     EXTERIOR       
  6, front-door    OPAQ  VERT  D_mtl_EPS    EXTERIOR       
  7, right         OPAQ  VERT  B_wall_pony  EXTERIOR       
  8, right-aper    TRAN  VERT  WNDW_200     EXTERIOR       
  9, right-frame   OPAQ  VERT  FRM_wood     EXTERIOR       
 10, back          OPAQ  VERT  B_wall_cc    BASESIMP       
 11, left          OPAQ  VERT  B_wall_cc    BASESIMP       
#END_SURFACE_ATTRIBUTES
#BASE: list of floor surface ID numbers (must have six elements), area of base (m^2); also leave the final line after this next line
1 0 0 0 0 0 84.5 0
