#!/bin/sh

prompt_input_yN()
{
    printf "${1}? [y|N] " ; shift
    while true; do
        read -k 1 yn
        case ${yn} in
            [Yy]* ) printf "\n"; return 0; break;;
            \n ) printf "\n"; return 1; break;;
            * ) return 1;;
        esac
    done
}

build_boost()
{
    wd=${USER_GIT_ROOT}/boost
    if [ ! -d ${wd} ]; then
        git clone --recursive \
                  --single-branch \
                  --branch boost-1.66.0 \
                  git@github.com:boostorg/boost.git \
                  ${wd}
    fi
    cd ${wd}

    prompt_input_yN "git clean" && git clean -fdx && git checkout .

    mkdir -p {build,release}

    ./bootstrap.sh \
        --with-toolset=clang
    ./b2 \
        --ignore-site-config \
        -j${NPROC} \
        --prefix=${wd}/release \
        toolset=clang \
        threading=multi \
        headers
    ./b2 \
        --ignore-site-config \
        -j${NPROC} \
        --prefix=${wd}/release \
        toolset=clang \
        threading=multi \
        install
}

build_eos()
{
    NPROC=$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN 2>/dev/null || echo 1)
    export NPROC

    prompt_input_yN "build secp256k1-zkp" && build_secp256k1
    prompt_input_yN "build boost" && build_boost
    prompt_input_yN "build eos" || return 0

    if [ "${USER_GIT_ROOT}" = "" ]; then
        printf "absolute path to clone required projects into, USER_GIT_ROOT="
        read USER_GIT_ROOT
    fi
    case "${USER_GIT_ROOT}" in
        /*) ;;
        *) printf "error: not an absolute path\n"; return 1 ;;
    esac
    export USER_GIT_ROOT
    mkdir -p ${USER_GIT_ROOT}

    wd=${USER_GIT_ROOT}/eos
    if [ ! -d ${wd} ]; then
        git clone --recursive git@github.com:EOSIO/eos.git ${wd}
    fi
    pwd=$(pwd)
    cd ${wd}

    prompt_input_yN "git clean" && git clean -fdx && git checkout .
    git fetch --all
    if prompt_input_yN "checkout specific tag"; then
        git tag
        printf "tag="
        read tag
    fi
    if prompt_input_yN "git pull"; then
        git checkout ${tag}
        git pull origin ${tag}
        git submodule sync
        git submodule update --init --recursive
    fi
    prompt_input_yN "install to system prefix" \
        || INSTALL_PREFIX="-DCMAKE_INSTALL_PREFIX=${WD}/release"

    mkdir -p {build,release}
    cd build

    cmake \
        -DCMAKE_C_COMPILER=/usr/lib/llvm/4/bin/clang \
        -DBOOST_ROOT=${USER_GIT_ROOT}/boost/release \
        -DSecp256k1_ROOT_DIR=${USER_GIT_ROOT}/secp256k1-zkp/release \
        -DLLVM_DIR=/usr/lib/llvm/4/lib64/cmake/llvm \
        -DWASM_ROOT=/usr/lib/llvm/4 \
        ${INSTALL_PREFIX} \
        ..
    make -j${NPROC} install

    cd ${pwd}
}

build_secp256k1()
{
    wd=${USER_GIT_ROOT}/secp256k1-zkp
    if [ ! -d ${wd} ]; then
        git clone git@github.com:cryptonomex/secp256k1-zkp.git ${wd}
    fi
    cd ${wd}

    if prompt_input_yN "git clean"; then
        git clean -fdx
        git checkout .
    fi

    ./autogen.sh
    ./configure --prefix=${wd}/release
    gmake -j${NPROC} install
}

#check_deps()
#{
#}

