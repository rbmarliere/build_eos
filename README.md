# Build scripts for EOS.IO software

#### The scripts use /bin/zsh as the shell and require the environment variable $GIT_DIR to be set, for example:
```zsh
mkdir -p ~/git && export GIT_DIR=~/git
```

#### You should also put the scripts directory on your $PATH to make things easier:
```zsh
export PATH=/path_to_this_repo:$PATH
```

#### Then, to build EOS and its dependencies you would do:

```zsh
build_secp256k1-zkp
build_bynarien
build_boost
build_llvm
branch=dawn-v2.0.0 build_eos
```

#### If all went well you could use these aliases to help:

```zsh
alias eosc="~/git/eos/build/programs/eosc/eosc -H testnet1.eos.io -p 80"
alias eoscpp="$GIT_DIR/eos/build/tools/eoscpp"
alias eosd="$GIT_DIR/eos/build/programs/eosd/eosd --data-dir=$GIT_DIR/eos/data-dir --genesis-json=$GIT_DIR/eos/genesis.json"
alias eos-walletd="$GIT_DIR/eos/build/programs/eos-walletd/eos-walletd"
```

#### Note that you should put those aliases and the exports ($GIT_DIR and $PATH) in your shell runcom file (~/.zshrc).

