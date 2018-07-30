#!/bin/sh

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

build_boost()
{
    export PATH=/usr/lib/llvm/4/bin:${PATH}

    WD=${USER_GIT_ROOT}/boost
    if [ ! -d ${WD} ]; then
        git clone --recursive \
                  --single-branch \
                  --branch boost-1.67.0 \
                  git@github.com:boostorg/boost.git \
                  ${WD}
    fi
    cd ${WD}

    if prompt_input_yN "git clean and checkout"; then
        git clean -fdx
        git checkout .
    fi

    mkdir -p {build,release}

    ./bootstrap.sh \
        --with-toolset=clang
    ./b2 \
        --ignore-site-config \
        -j${NPROC} \
        --prefix=${WD}/release \
        --with-test \
        toolset=clang \
        threading=multi \
        headers
    ./b2 \
        --ignore-site-config \
        -j${NPROC} \
        --prefix=${WD}/release \
        --with-test \
        toolset=clang \
        threading=multi \
        install
}

build_eos()
{
    NPROC=$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN 2>/dev/null || echo 1)
    export NPROC

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

    prompt_input_yN "build secp256k1-zkp" && build_secp256k1
    if prompt_input_yN "build llvm"; then
        prompt_input_yN "install to system prefix (use portage)" && build_llvm_funtoo || build_llvm_out
    fi
    prompt_input_yN "build boost" && build_boost
    prompt_input_yN "build eos" || return 0

    WD=${USER_GIT_ROOT}/eos
    if [ ! -d ${WD} ]; then
        git clone --recursive git@github.com:EOS-Mainnet/eos.git ${WD}
    fi
    PWG=$(pwd)
    cd ${WD}

    if prompt_input_yN "git clean and checkout"; then
        git clean -fdx 2>/dev/null || sudo git clean -fdx
        git checkout .
    fi
    git branch
    if prompt_input_yN "checkout specific tag"; then
        git fetch --all
        git tag
        printf "TAG="
        read TAG
    fi
    if prompt_input_yN "git pull"; then
        git checkout ${TAG}
        git pull origin ${TAG}
        git submodule sync
        git submodule update --init --recursive
    fi

    if prompt_input_yN "install to custom prefix"; then
        printf "absolute release path, INSTALL_PREFIX="
        read INSTALL_PREFIX
        case "${INSTALL_PREFIX}" in
            /*) ;;
            *) printf "error: not an absolute path\n"; return 1 ;;
        esac
        mkdir -p ${INSTALL_PREFIX}
        INSTALL_PREFIX="-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}"
    fi

    CXX_COMPILER=/usr/lib/llvm/4/bin/clang++
    C_COMPILER=/usr/lib/llvm/4/bin/clang
    LLVM_DIR=/usr/lib/llvm/4/lib64/cmake/llvm
    WASM_ROOT=/usr/lib/llvm/4
    if [ -d ${USER_GIT_ROOT}/llvm/release ] \
    && prompt_input_yN "use custom llvm"; then
        CXX_COMPILER=${USER_GIT_ROOT}/llvm/release/bin/clang++
        C_COMPILER=${USER_GIT_ROOT}/llvm/release/bin/clang
        LLVM_DIR=${USER_GIT_ROOT}/llvm/release
        WASM_ROOT=${USER_GIT_ROOT}/llvm/release
    fi

    mkdir -p build
    cd build

    cmake \
        ${INSTALL_PREFIX} \
        -DBOOST_ROOT=${USER_GIT_ROOT}/boost/release \
        -DCMAKE_CXX_COMPILER=${CXX_COMPILER} \
        -DCMAKE_C_COMPILER=${C_COMPILER} \
        -DCMAKE_EXE_LINKER_FLAGS="-lpthread -lLLVMInstCombine -lLLVMTransformUtils -lLLVMScalarOpts -lLLVMExecutionEngine -lLLVMObject -lLLVMRuntimeDyld" \
        -DLLVM_DIR=${LLVM_DIR} \
        -DSecp256k1_ROOT_DIR=${USER_GIT_ROOT}/secp256k1-zkp/release \
        -DWASM_ROOT=${WASM_ROOT} \
        ..
    make -j${NPROC}
    prompt_input_yN "sudo make install" && sudo make install

    cd ${PWD}
}

build_llvm_funtoo()
{
    PWD=$(pwd)
    cd

    if [ ! -f /etc/portage/repos.conf/llvm_wasm ]; then
        cat > llvm_wasm << EOF
[DEFAULT]
main-repo = core-kit
[llvm_wasm]
location = /var/git/llvm_wasm
auto-sync = no
priority = 10
EOF
        sudo mv llvm_wasm /etc/portage/repos.conf/
    fi

    if [ "$(groups | grep portage)" = "" ]; then
        sudo usermod -aG portage $(whoami)
    fi

    if [ -d /var/git/llvm_wasm ]; then
        git --git-dir=/var/git/llvm_wasm/.git --work-tree=/var/git/llvm_wasm pull origin
    else
        git clone git@github.com:zrts/llvm_wasm.git
        sudo chmod g+w /var/git
        sudo mv llvm_wasm /var/git
    fi

    if [ -d /etc/portage/package.use ]; then
        if [ ! -f /etc/portage/package.use/llvm ]; then
            printf "=sys-devel/llvm-4.0.1-r1::llvm_wasm wasm" > llvm
            sudo mv llvm /etc/portage/package.use
        fi
    else
        USE_LINE="=sys-devel/llvm-4.0.1-r1::llvm_wasm wasm"
        if [ "$(grep ${USE_LINE} /etc/portage/package.use)" = "" ]; then
            sudo cat /etc/portage/package.use > package.use
            printf "${USE_LINE}" >> package.use
            sudo mv package.use /etc/portage
        fi
    fi

    sudo ego sync
    sudo emerge "=sys-devel/clang-4.0.1" "=sys-devel/llvm-4.0.1-r1::llvm_wasm"

    cd ${PWD}
}

build_llvm_out()
{
    WD=${USER_GIT_ROOT}/llvm
    if [ ! -d ${WD} ]; then
        git clone \
            --depth 1 \
            --single-branch \
            --branch release_40 \
            git@github.com:llvm-mirror/llvm.git ${WD}
        git clone \
            --depth 1 \
            --single-branch \
            --branch release_40 \
            git@github.com:llvm-mirror/clang.git ${WD}/tools/clang
    fi

    cd ${WD}
    if prompt_input_yN "git clean and checkout"; then
        git clean -fdx
        git checkout .
    fi
    mkdir {build,release}
    cd build

    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_COMPILER=/usr/lib/llvm/4/bin/clang++ \
        -DCMAKE_C_COMPILER=/usr/lib/llvm/4/bin/clang \
        -DCMAKE_INSTALL_PREFIX=${WD}/release \
        -DCORE_SYMBOL_NAME="EOS" \
        -DLLVM_ENABLE_RTTI=On \
        -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly \
        -DLLVM_TARGETS_TO_BUILD=X86 \
        -G "Unix Makefiles" \
        ..
    make -j${NPROC} install
}

build_secp256k1()
{
    WD=${USER_GIT_ROOT}/secp256k1-zkp
    if [ ! -d ${WD} ]; then
        git clone git@github.com:cryptonomex/secp256k1-zkp.git ${WD}
    fi
    cd ${WD}

    if prompt_input_yN "git clean and checkout"; then
        git clean -fdx
        git checkout .
    fi

    ./autogen.sh
    ./configure --prefix=${WD}/release
    gmake -j${NPROC} install
}

