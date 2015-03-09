#!/bin/bash

tar -xf Array-Compare-1.15.tar.gz
cd Array-Compare-1.15
perl Makefile.PL
make
make install
cd ..

tar -xf Clone-0.36.tar.gz
cd Clone-0.36
perl Makefile.PL
make
make install
cd ..

tar -xf CSV-2.0.tar.gz
cd CSV-2
perl Makefile.PL
make
make install
cd ..

tar -xf Data-Dumper-2.145.tar.gz
cd Data-Dumper-2.145
perl Makefile.PL
make
make install
cd ..

tar -xf File-Path-2.04.tar.gz
cd File-Path-2.04
perl Makefile.PL
make
make install
cd ..

tar -xf Hash-Merge-0.11.tar.gz
cd Hash-Merge-0.11
perl Makefile.PL
make
make install
cd ..

tar -xf local-lib-1.008004.tar.gz
cd local-lib-1.008004
perl Makefile.PL
make
make install
cd ..

tar -xf threads-1.89.tar.gz
cd threads-1.71
perl Makefile.PL
make
make install
cd ..

tar -xf XML-Dumper-0.81.tar.gz
cd XML-Dumper-0.81
perl Makefile.PL
make
make install
cd ..

tar -xf XML-Simple-2.18.tar.gz
cd XML-Simple-2.18
perl Makefile.PL
make
make install
cd ..

tar -xf Math-Polygon-1.02.tar.gz
cd Math-Polygon-1.02
perl Makefile.PL
make
make install
cd ..