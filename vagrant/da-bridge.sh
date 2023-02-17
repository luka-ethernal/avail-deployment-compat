#! /bin/bash

if test -f .setup; then
  echo "Setup already done."
else
  #  setup environment for running hardhat and solidity deploy
  echo "deb http://security.ubuntu.com/ubuntu focal-security main" | sudo tee /etc/apt/sources.list.d/nodesource.list
  sudo apt-get -y update
  sudo apt install curl git
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash -
  sudo apt-get install -y gcc g++ make jq nodejs cargo rustc
  sudo apt-get install -y libssl1.1

  rustup update stable
  source "$HOME/.cargo/env"
  cargo install --git https://github.com/foundry-rs/foundry --profile local --locked foundry-cli anvil

  mkdir /home/vagrant/hardhat && cd /home/vagrant/hardhat && npm install --save-dev hardhat
  cp /home/vagrant/sync_folder/da-bridge/hardhat.config.js /home/vagrant/hardhat/ || exit 1

  touch .setup
fi

MONOREPO_SOURCE=/home/vagrant/sync_folder/da-bridge/monorepo
AGENTS_HOME=/home/vagrant/agents
AGENTS_SYNC=/home/vagrant/sync_folder/da-bridge/agents

echo "Restarting hardhat"
sudo lsof -n -i:8545 | grep LISTEN | awk '{ print $2 }' | uniq | xargs kill -9
cd /home/vagrant/hardhat && npx hardhat node &>/home/vagrant/hardhat/hardhat_logs.txt &

echo "Deploy contracts to hardhat"
cd $MONOREPO_SOURCE/packages/contracts-da-bridge || exit 1
export $(grep -v '^#' $MONOREPO_SOURCE/packages/contracts-da-bridge/.env | xargs)
forge script contracts/script/DeployDemo.s.sol --rpc-url $GOERLI_RPC_URL --broadcast -vvvv --private-key $PRIVATE_KEY --slow

echo "Move agents"
rm -rf $AGENTS_HOME && mkdir -p $AGENTS_HOME
cd $AGENTS_SYNC || exit 1
cp config_local.json .env_local $AGENTS_HOME
cd /home/vagrant || exit 1
mkdir -m777 -p $AGENTS_HOME/{updater,relayer,processor,watcher}
cp -r $AGENTS_SYNC/updater $AGENTS_HOME/updater/
cp -r $AGENTS_SYNC/relayer $AGENTS_HOME/relayer/
cp -r $AGENTS_SYNC/processor $AGENTS_HOME/processor/
cp -r $AGENTS_SYNC/watcher $AGENTS_HOME/watcher/

# Extract addresses based on the latest contract deployment
cd $MONOREPO_SOURCE/broadcast/DeployDemo.s.sol/31337/ || exit 1
export HOME=$(jq '.transactions[] | select(.contractName=="Home") | .contractAddress' run-latest.json | head -n 1)
export REPLICA=$(jq '.transactions[] | select(.contractName=="Replica") | .contractAddress' run-latest.json | head -n 1)
export BRIDGE=$(jq '.transactions[] | select(.contractName=="DABridgeRouter") | .contractAddress' run-latest.json | head -n 1)
export MANAGER=$(jq '.transactions[] | select(.contractName=="XAppConnectionManager") | .contractAddress' run-latest.json | head -n 1)

#  Update configuration based on the deployed contracts
jq ".core.goerli.home.proxy=$HOME" $AGENTS_HOME/config_local.json >$AGENTS_HOME/config.json && mv $AGENTS_HOME/config.json $AGENTS_HOME/config_local.json
jq ".core.goerli.replicas.avail.proxy=$REPLICA" $AGENTS_HOME/config_local.json >$AGENTS_HOME/config.json && mv $AGENTS_HOME/config.json $AGENTS_HOME/config_local.json
jq ".bridge.goerli.bridgeRouter.proxy=$BRIDGE" $AGENTS_HOME/config_local.json >$AGENTS_HOME/config.json && mv $AGENTS_HOME/config.json $AGENTS_HOME/config_local.json
jq ".core.goerli.xAppConnectionManager=$MANAGER" $AGENTS_HOME/config_local.json >$AGENTS_HOME/config.json && mv $AGENTS_HOME/config.json $AGENTS_HOME/config_local.json

echo "Start agents"
cd $AGENTS_HOME || exit 1
cd updater && env $(cat ../.env_local | xargs) ./updater &>./updater_logs.txt &
cd relayer && env $(cat ../.env_local | xargs) ./relayer &>./relayer_logs.txt &
cd processor && env $(cat ../.env_local | xargs) ./processor &>./processor_logs.txt &
cd watcher && env $(cat ../.env_local | xargs) ./watcher &>./watcher_logs.txt &

