#!/bin/bash

set -ex

ssh root@napkin << EOF
set -ex
GO_VERSION="1.18"

# apt-get update

apt-get install -y \
  ruby-full \
  python3.10-full \
  python3-pip \
  sqlite3 \
  libsqlite3-dev \
  gnuplot-nox \
  linux-tools-\$(uname -r) \
  linux-cloud-tools-\$(uname -r) \
  build-essential \
  fzf \
  ripgrep \
  universal-ctags \
  gdb \
  clang \
  libssl-dev \
  pkg-config \
  valgrind \
  bpftrace \
  bpfcc-tools \
  ca-certificates \
  gnupg \
  curl \
  mosh \
  lsb-release \
  python-is-python3 \
  tmux \
  nasm \
  msr-tools \
  software-properties-common

if ! command -v psql; then
  sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt \$(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
  apt-get update
  apt-get -y install postgresql
  systemctl start postgresql.service
  sudo -u postgres createuser --superuser root || true
  sudo -u postgres createdb root || true
  echo 'host    all             all             0.0.0.0/0               trust' >> /etc/postgresql/*/main/pg_hba.conf

  # listen on tailscale IP
fi

if ! command -v go; then
  wget -nc https://go.dev/dl/go\$GO_VERSION.linux-amd64.tar.gz
  sudo tar -C /usr/local -xzf go\$GO_VERSION.linux-amd64.tar.gz

  echo 'export PATH=\$PATH:/usr/local/go/bin' >> ~/.bashrc
  rm *.tar.gz
fi

if ! command -v rustc; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

if ! command -v docker; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
fi

if ! command -v docker-compose; then
  # https://docs.docker.com/compose/install/
  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

if ! command -v nvim; then
  add-apt-repository ppa:neovim-ppa/stable
  apt-get update
  apt-get install -y neovim
  echo 'alias vim=nvim' >> ~/.bashrc
fi

if ! command -v delta; then
  wget https://github.com/dandavison/delta/releases/download/0.12.1/git-delta_0.12.1_amd64.deb
  dpkg -i git-delta_0.12.1_amd64.deb
fi

if ! command -v nvm; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
  (
    . ~/.bashrc
    nvm install stable
  )
fi

if ! command -v chruby; then
  (
    wget -O chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
    tar -xzvf chruby-0.3.9.tar.gz
    cd chruby-0.3.9/
    sudo make install
    echo 'source /usr/local/share/chruby/chruby.sh' >> ~/.bashrc
    cd ..

    wget -O ruby-install-0.8.3.tar.gz https://github.com/postmodern/ruby-install/archive/v0.8.3.tar.gz
    tar -xzvf ruby-install-0.8.3.tar.gz
    cd ruby-install-0.8.3/
    sudo make install

    . ~/.bashrc

    ruby-install --jobs \$(nproc) ruby
    chruby ruby
    gem install bundler

    echo 'chruby ruby' >> ~/.bashrc

    cd ..
    rm -rf chruby-*
    rm -rf ruby-install-*
  )
fi

if [ ! -d ~/pmu-tools ]; then
  git clone https://github.com/andikleen/pmu-tools ~/pmu-tools
  echo 'export PATH=\$PATH:~/pmu-tools' >> ~/.bashrc
fi

if [ ! -d ~/uarch-bench ]; then
  git clone --recursive https://github.com/travisdowns/uarch-bench ~/uarch-bench
fi

if [ ! -d ~/likwid ]; then
  git clone https://github.com/RRZE-HPC/likwid ~/likwid
fi

if [ ! -d ~/bcc ]; then
  git clone https://github.com/iovisor/bcc ~/bcc
fi

if [ ! -d ~/flamegraph ]; then
  # https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html#Instructions
  git clone https://github.com/brendangregg/FlameGraph ~/flamegraph
  echo 'export PATH=\$PATH:~/flamegraph' >> ~/.bashrc
fi

apt-get upgrade -y
apt-get autoremove -y

EOF

script/sync

ssh root@napkin << EOF
set -ex

cd napkin
RUSTFLAGS='-C target-cpu=native' cargo build --release
RUSTFLAGS='-C target-cpu=native' cargo bench DONTRUNANYTHING
EOF