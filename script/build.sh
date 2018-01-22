#!/usr/bin/env bash

CC=gcc
CXX=g++

# use gmake under FreeBSD
if [ `uname` = "FreeBSD" ]; then
  MAKE=gmake
  CC=clang
  CXX=clang++
else
  MAKE=make
fi

export CC CXX CFLAGS MAKE

# check required programs
REQ_PROG_LIST="${CXX} ${CC} unzip bison flex ${MAKE} makeinfo patch"

# MinGW doesn't have curl, so we use wget.
if uname|grep "^MINGW32" > /dev/null; then
  USE_WGET=1
fi

# use curl or wget?
if [ ! -z $USE_WGET ]; then
  REQ_PROG_LIST+=" wget"
else
  REQ_PROG_LIST+=" curl"
fi

for REQ_PROG in $REQ_PROG_LIST; do
  if ! which $REQ_PROG > /dev/null; then
    echo "$REQ_PROG not installed"
    exit 1
  fi
done

# check GNU sed is installed or not.
# It is for OSX, which doesn't ship with GNU sed.
if ! sed --version 2>/dev/null |grep "GNU sed" > /dev/null ;then
  echo GNU sed is not installed, need to download.
  SED_VERSION=4.2.2
  SED_ARCHIVE="http://ftp.gnu.org/gnu/sed/sed-${SED_VERSION}.tar.bz2"
else
  SED_ARCHIVE=""
fi

# check zlib is installed
if ! ${CC} test-zlib.c -o test-zlib -lz; then
  echo "zlib not installed"
  exit 1
fi
rm test-zlib 2>/dev/null
rm test-zlib.exe 2>/dev/null

# djcross-gcc-X.XX-tar.* maybe moved from /djgpp/rpms/ to /djgpp/deleted/rpms/ directory.
OLD_DJCROSS_GCC_ARCHIVE=${DJCROSS_GCC_ARCHIVE/rpms\//deleted\/rpms\/}

# download source files
ARCHIVE_LIST="$BINUTILS_ARCHIVE $DJCRX_ARCHIVE $DJLSR_ARCHIVE $DJDEV_ARCHIVE
              $SED_ARCHIVE $DJCROSS_GCC_ARCHIVE $OLD_DJCROSS_GCC_ARCHIVE $GCC_ARCHIVE
              $AUTOCONF_ARCHIVE $AUTOMAKE_ARCHIVE"

echo "Download source files..."
mkdir -p download || exit 1
cd download

for ARCHIVE in $ARCHIVE_LIST; do
  FILE=`basename $ARCHIVE`
  if ! [ -f $FILE ]; then
    echo "Download $ARCHIVE ..."
    if [ ! -z $USE_WGET ]; then
      DL_CMD="wget -U firefox $ARCHIVE"
    else
      DL_CMD="curl -f $ARCHIVE -L -o $FILE"
    fi
    echo "Command : $DL_CMD"
    if ! eval $DL_CMD; then
      if [ "$ARCHIVE" == "$DJCROSS_GCC_ARCHIVE" ]; then
        echo "$FILE maybe moved to deleted/ directory."
      else
        rm $FILE
        echo "Download $ARCHIVE failed."
        exit 1
      fi
    fi
  fi
done
cd ..

# create target directory, check writable.
echo "Make prefix directory : $DJGPP_PREFIX"
mkdir -p $DJGPP_PREFIX

if ! [ -d $DJGPP_PREFIX ]; then
  echo "Unable to create prefix directory"
  exit 1
fi

if ! [ -w $DJGPP_PREFIX ]; then
  echo "prefix directory is not writable."
  exit 1
fi

# make build dir
echo "Make build dir"
mkdir -p build || exit 1
cd build

if [ ! -e ${DJGPP_PREFIX}/etc/binutils-${BINUTILS_VERSION}-installed ]; then
  # build binutils
  echo "Building binutils"
  rm -rf bnu${BINUTILS_VERSION}s
  mkdir bnu${BINUTILS_VERSION}s
  cd bnu${BINUTILS_VERSION}s
  unzip -o ../../download/bnu${BINUTILS_VERSION}s.zip || exit 1
  cd gnu/binutils-* || exit
  
  # exec permission of some files are not set, fix it.
  for EXEC_FILE in install-sh missing; do
    echo "chmod a+x $EXEC_FILE"
    chmod a+x $EXEC_FILE || exit 1
  done
  
  sh ./configure \
             --prefix=$DJGPP_PREFIX \
             --target=i586-pc-msdosdjgpp \
             --program-prefix=i586-pc-msdosdjgpp- \
             --disable-werror \
             --disable-nls \
             || exit 1
  
  ${MAKE} -j${MAKE_JOBS} configure-bfd || exit 1
  ${MAKE} -j${MAKE_JOBS} -C bfd stmp-lcoff-h || exit 1
  ${MAKE} -j${MAKE_JOBS} || exit 1
  
  if [ ! -z $MAKE_CHECK ]; then
    echo "Run ${MAKE} check"
    ${MAKE} -j${MAKE_JOBS} check || exit 1
  fi
  
  ${MAKE} -j${MAKE_JOBS} install || exit 1
  
  cd ../../..
  rm ${DJGPP_PREFIX}/etc/binutils-*-installed
  touch ${DJGPP_PREFIX}/etc/binutils-${BINUTILS_VERSION}-installed
  # binutils done
else
  echo "Current binutils version already installed, skipping."
fi

# prepare djcrx
echo "Prepare djcrx"
mkdir djcrx${DJCRX_VERSION}
cd djcrx${DJCRX_VERSION}
unzip -o ../../download/djcrx${DJCRX_VERSION}.zip || exit 1
patch -p1 -u < ../../patch/patch-djcrx205.txt || exit 1

cd src/stub
${CC} -O2 stubify.c -o stubify || exit 1
${CC} -O2 stubedit.c -o stubedit || exit 1

cd ../..

mkdir -p $DJGPP_PREFIX/i586-pc-msdosdjgpp/sys-include || exit 1
cp -rp include/* $DJGPP_PREFIX/i586-pc-msdosdjgpp/sys-include/ || exit 1
cp -rp lib $DJGPP_PREFIX/i586-pc-msdosdjgpp/ || exit 1
cp -p src/stub/stubify $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/ || exit 1
cp -p src/stub/stubedit $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/ || exit 1

cd ..
# djcrx done

# build gcc
tar -xjvf ../download/djcross-gcc-${GCC_VERSION}.tar.bz2 || exit 1
cd djcross-gcc-${GCC_VERSION}/

BUILDDIR=`pwd`

if [ ! -e ${BUILDDIR}/tmpinst/autoconf-${AUTOCONF_VERSION}-built ]; then
  echo "Building autoconf"
  cd $BUILDDIR
  tar xJf ../../download/autoconf-${AUTOCONF_VERSION}.tar.xz || exit 1
  cd autoconf-${AUTOCONF_VERSION}/
  ./configure --prefix=$BUILDDIR/tmpinst || exit 1
  ${MAKE} -j${MAKE_JOBS} all install || exit 1
  rm ${BUILDDIR}/tmpinst/autoconf-*-built
  touch ${BUILDDIR}/tmpinst/autoconf-${AUTOCONF_VERSION}-built
else
  echo "autoconf already built, skipping."
fi

if [ ! -e ${BUILDDIR}/tmpinst/automake-${AUTOMAKE_VERSION}-built ]; then
  echo "Building automake"
  cd $BUILDDIR
  tar xJf ../../download/automake-${AUTOMAKE_VERSION}.tar.xz || exit 1
  cd automake-${AUTOMAKE_VERSION}/
  PATH="$BUILDDIR//tmpinst/bin:$PATH" \
  ./configure --prefix=$BUILDDIR/tmpinst || exit 1
  PATH="$BUILDDIR//tmpinst/bin:$PATH" \
  ${MAKE} all install || exit 1
  rm ${BUILDDIR}/tmpinst/automake-*-built
  touch ${BUILDDIR}/tmpinst/automake-${AUTOMAKE_VERSION}-built
else
  echo "automake already built, skipping."
fi

# build GNU sed if needed.
SED=sed
if [ ! -z $SED_VERSION ]; then
  echo "Building sed"
  cd $BUILDDIR
  tar xjf ../../download/sed-${SED_VERSION}.tar.bz2 || exit 1
  cd sed-${SED_VERSION}/
  ./configure --prefix=$BUILDDIR/tmpinst || exit 1
  ${MAKE} -j${MAKE_JOBS} all install || exit 1
  SED=$BUILDDIR/tmpinst/bin/sed
fi

cd $BUILDDIR

if [ ! -e gcc-unpacked ]; then
  # gcc 4.8 or above unpack-gcc.sh needs to be patched for OSX
  # patch from :
  #   ( cd gnu && tar xf $top/$archive $tar_param && echo $archive >$top/s-sources )
  # to :
  #   ( cd gnu && tar xJf $top/$archive && echo $archive >$top/s-sources )
  echo "Patch unpack-gcc.sh"
  $SED -i "s/\(cd gnu && tar x\)\(f [^ ]* \)\([^ ]* \)/\1J\2/" unpack-gcc.sh || exit 1
  if [ `uname` = "FreeBSD" ]; then
    # The --verbose option is not recognized by BSD patch
    $SED -i 's/patch --verbose/patch/' unpack-gcc.sh || exit 1
  fi
  
  echo "Running unpack-gcc.sh"
  PATH="$BUILDDIR/tmpinst/bin:$PATH" sh unpack-gcc.sh --no-djgpp-source ../../download/gcc-${GCC_VERSION}.tar.xz || exit 1
  
  # patch gnu/gcc-X.XX/gcc/doc/gcc.texi
  echo "Patch gcc/doc/gcc.texi"
  cd gnu/gcc-*/gcc/doc || exit 1
  $SED -i "s/[^^]@\(\(tex\)\|\(end\)\)/\n@\1/g" gcc.texi || exit 1
  cd -
  
  # copy stubify programs
  cp $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/stubify $BUILDDIR/tmpinst/bin
  
  cd $BUILDDIR/
  
  # download mpc/gmp/mpfr/isl libraries
  echo "Downloading gcc dependencies"
  cd gnu/gcc-${GCC_VERSION_SHORT}
  ./contrib/download_prerequisites
  cd -
  
  touch gcc-unpacked
else
  echo "gcc already unpacked, skipping."
fi

echo "Building gcc"

mkdir -p djcross || exit 1
cd djcross

if [ ! `cat gcc-configure-prefix` = "${DJGPP_PREFIX}" ]; then
  PATH="$BUILDDIR//tmpinst/bin:$PATH" \
  ../gnu/gcc-${GCC_VERSION_SHORT}/configure \
                                   --target=i586-pc-msdosdjgpp \
                                   --program-prefix=i586-pc-msdosdjgpp- \
                                   --prefix=$DJGPP_PREFIX \
                                   --disable-nls \
                                   --disable-plugin \
                                   --enable-lto \
                                   --enable-libstdcxx-filesystem-ts \
                                   --enable-libquadmath-support \
                                   --enable-version-specific-runtime-libs \
                                   --enable-languages=${ENABLE_LANGUAGES} \
                                   || exit 1
  echo ${DJGPP_PREFIX} > gcc-configure-prefix
else
  echo "Note: gcc already configured. To force a rebuild, use: rm -rf ${BUILDDIR}/djcross/"
  sleep 5
fi

${MAKE} -j${MAKE_JOBS} "PATH=$BUILDDIR/tmpinst/bin:$PATH" || exit 1

${MAKE} -j${MAKE_JOBS} install-strip || exit 1

echo "Copy long name executables to short name."
(
  cd $DJGPP_PREFIX || exit 1
  SHORT_NAME_LIST="gcc g++ c++ addr2line c++filt cpp size strings"
  for SHORT_NAME in $SHORT_NAME_LIST; do
    if [ -f bin/i586-pc-msdosdjgpp-gcc ]; then
      cp bin/i586-pc-msdosdjgpp-$SHORT_NAME i586-pc-msdosdjgpp/bin/$SHORT_NAME
    fi
  done
) || exit 1

# gcc done

# build djlsr (for dxegen / exe2coff)
echo "Prepare djlsr"
cd $BUILDDIR
cd ..
rm -rf djlsr${DJLSR_VERSION}
mkdir djlsr${DJLSR_VERSION}
cd djlsr${DJLSR_VERSION}
unzip ../../download/djlsr${DJLSR_VERSION}.zip || exit 1
unzip -o ../../download/djdev${DJDEV_VERSION}.zip "include/*/*" || exit 1
unzip -o ../../download/djdev${DJDEV_VERSION}.zip "include/*" || exit 1
patch -p1 -u < ../../patch/patch-djlsr205.txt || exit 1
if [ "$CC" == "gcc" ]; then
  echo "Building DXE tools."
  cd src
  PATH=$DJGPP_PREFIX/bin/:$PATH ${MAKE} || exit 1
  cp dxe/dxegen dxe/dxe3gen dxe/dxe3res $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/ || exit 1
  cd ..
else
  echo "Building DXE tools requires gcc, skip."
fi
cd src/stub
${CC} -o exe2coff exe2coff.c || exit 1
cp -p exe2coff $DJGPP_PREFIX/i586-pc-msdosdjgpp/bin/ || exit 1
cd ../../..
# djlsr done

# copy setenv script
(cd $BUILDDIR/../../setenv/ && ./copyfile.sh $DJGPP_PREFIX) || exit 1

echo "Testing DJGPP."
cd $BUILDDIR
cd ..
echo "Use DJGPP to build a test C program."
$DJGPP_PREFIX/bin/i586-pc-msdosdjgpp-gcc ../hello.c -o hello || exit 1

for x in $(echo $ENABLE_LANGUAGES | tr "," " ")
do
  case $x in
    c++)
      echo "Use DJGPP to build a test C++ program."
      $DJGPP_PREFIX/bin/i586-pc-msdosdjgpp-c++ ../hello-cpp.cpp -o hello-cpp || exit 1
      ;;
  esac
done

echo "build-djgpp.sh done. To remove temporary build files, use: rm -rf build/"
