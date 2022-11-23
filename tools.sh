#!/bin/bash
set -e
set +x

###
# Install autoconf, automake and libtool smoothly on Mac OS X.
# Newer versions of these libraries are available and may work better on OS X
#

export TOOL="tools" # or wherever you'd like to build

if [[ ! -d $TOOL ]]; then
    mkdir -p $TOOL
fi

##
# Autoconf
# http://ftpmirror.gnu.org/autoconf

pushd .
cd $TOOL
curl -OL http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
tar xzf autoconf-2.69.tar.gz
cd autoconf-2.69
./configure --prefix=/usr/local
make
sudo make install
export PATH=$PATH:/usr/local/bin
popd;

##
# Automake
# http://ftpmirror.gnu.org/automake

pushd .
cd $TOOL
curl -OL http://ftpmirror.gnu.org/automake/automake-1.15.tar.gz
tar xzf automake-1.15.tar.gz
cd automake-1.15
./configure --prefix=/usr/local
make
sudo make install
popd;

##
# Libtool
# http://ftpmirror.gnu.org/libtool

pushd .
cd $TOOL
curl -OL http://ftpmirror.gnu.org/libtool/libtool-2.4.6.tar.gz
tar xzf libtool-2.4.6.tar.gz
cd libtool-2.4.6
./configure --prefix=/usr/local
make
sudo make install
popd;

echo "Installation complete."