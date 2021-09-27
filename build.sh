#!/bin/sh

PYSET=0
PYTHONEXEC=""
PYPY_VER=pypy2-v5.6.0
PYPY_FILE=$PYPY_VER-src.tar.bz2
PYPY_URL=https://bitbucket.org/pypy/pypy/downloads/$PYPY_FILE

check_dependencies() {
    # Dependencies check
    NOT_FOUND="not found"

    PKGCONFEXEC=$(which pkg-config);
    case $NOT_FOUND in
        *"$PKGCONFEXEC"*) echo "Please install pkg-config or add it to \$PATH."; exit 1;;
        *) echo "Found: pkg-config - $PKGCONFEXEC";;
    esac

    VENVEXEC=$(which virtualenv);
    case $NOT_FOUND in
        *"$VENVEXEC"*) echo "Is virtualenv installed? If so, make sure it is in \$PATH"; exit 1;;
        *) echo "Found: virtualenv - $VENVEXEC";;
    esac

    NO_LIBS="PKG_CONFIG_PATH"
    HAVE_LIBS=$(pkg-config --libs "libffi" "libuv" "libsodium");
    case $NO_LIBS in
        *"$HAVE_LIBS"*) echo "Please make sure development files for libffi, libuv, and libsodium are installed."; exit 1;;
        *) echo "Found: libffi, libuv, and libsodium - ${HAVE_LIBS}";;
    esac

    for PYEXEC in "python27" "python2.7"
    do
        PYTHONEXEC=$(which $PYEXEC)
        case $NOT_FOUND in
            *"$PYTHONEXEC"*) continue;;
            *) PYSET=1; break;;
        esac
    done
    case $PYSET in
        0) echo "Please make sure python 2.7 installed and available as python27 or 2.7 in \$PATH."; exit 1;;
        1) echo "Found: Python 2.7 - $PYTHONEXEC";;
    esac
}

setup_build_env() {
    # create-venv
    virtualenv -p $PYTHONEXEC venv/ && . venv/bin/activate

    # Install deps
    pip install -U pytest

    # Grab and extract rpython
    if [ ! -f $PYPY_FILE ]
    then
        wget $PYPY_URL
    fi
    tar -xf $PYPY_FILE --strip-components=1 $PYPY_VER-src/rpython/
}

build() {
    # build
    make && make testMast && make boot
}

all() {
    check_dependencies
    setup_build_env
    build
}

clean() {
    rm -f ./mt-typhon
}

clean_all() {
    rm -f ./$PYPY_FILE
    rm -rf ./rpython
    rm -rf ./venv
    clean
}


usage() {
    cat <<EOF
build.sh usage:
    build.sh [all | clean | cleanall | -h | --help]

    all        : build mt-typhon
    clean      : clean compiled/translated objects
    cleanall   : clean and remove cached files (pypy, rpython)
    -h | --help: display this usage info
    No args    : see 'all'

build.sh dependencies:
    pkg-config, python2.7, virtualenv, libsodium, libuv, libffi
EOF
}

case $1 in
    "") all;;
    "all") all;;
    "clean") clean;;
    "cleanall") clean_all;;
    "-h") usage;;
    "--help") usage;;
    *) usage; exit 1;;
esac



