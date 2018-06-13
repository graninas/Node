## Node

P2P node for the main network protocol.

The node acts as a carrier and data storage. Numerous nodes form a network to transmit arbitrtary data across: messages about new k-blocks, microblocks, transactions, events, etc. All the data carried between nodes is ecnrypted (asymmetric encryption).

Compiling the repo generates the following executables:

* BootNode-exe - a boot node that keeps a list of arbitrary available connected Simple Nodes and gives parts of that list on request to new Simple Nodes entering the network.
* SimpleNode-exe - a basic role of a node that receives transactions from LighClient (user light client), adds them to the mempool, sends PoA Nodes (mobile nodes) transactions from the mempool, receives generated microblocks from PoA Nodes and propagates those blocks over the network to other Simple Nodes. Also,it can receive requests to calculate wallet balance, give information on transactions and microblocks, and then give responses to those requests. In the future, it'll be used in the sharding implementation: data distribution management and data fetchon request.
* LightClien-exe - a user client that can generate new public keys (wallet addresses), generate transacations and send them to an arbitrary node (can be a local or remote node).

Node supports multithreading. Each thread has its own data and can read data from another thread, change its (.self) state, propagate messages to other actors and create new actors. This way we avoid numerous problems normally assosiated with multithreading and can process events in parallel balancing the available resources.

Node relies on actors. The central part of a node is the governing actor. It stores the main data, information about neighbor nodes and network status information. Other actors are reponsible for communication with the outside world processing incoming and outcoming messages.



## How to Use

### Install Haskell Stack

1. Install Haskell stack

`curl -sSL https://get.haskellstack.org/ | sh`

2. If needed, add the path to your profile

`sudo nano ~/.profile` and append `export PATH=$PATH:$HOME/.local/bin` at the end.


### Install Docker and Pull the Image

1. [Install Docker](https://docs.docker.com/install/linux/docker-ce/ubuntu/)

2. Add current user to the docker group

`sudo usermod -a -G docker $USER`

2.1 Log out or reboot

3. Pull Docker image (warning, ~2.6 Gb)

`stack docker pull`


### Clone and Build Node

1. Clone the repo

`git clone git@github.com:Enecuum/Node.git`

2. Build without docker

`stack build --no-docker`


### Initialize a Boot Node


`stack exec BootNode-exe`

### Initialize a Simple Node

`stack exec SimpleNode-exe`


### Initialize Light Client

Execute `stack exec LightClient-exe`.

#### Available commands for Light Client

| Command shortcut | Full command | Description |
|---------|--------|---------|
| -V, -? | --version | Show version number |
| -K | --get-public-key | Create new public key |
| -G qTx | --generate-n-transactions=qTx | Generate N transactions |
| -F | --generate-transactions | Generate transactions forever |
| -M | --show-my-keys | Show my public keys |
| -B publicKey | --get-balance=publicKey | Get balance for a public key |
| -S amount:to:from:currency | --send-money-to-from=amount:to:from:currency | Send currency from a public key to a public key (ENQ/ETH/DASH/BTC) |


### (Optional) Set your own environment variables:

You can define curstom values for variables in the /configs/config.json:

* `simpleNodeBuildConfig` is the config section for Simple Node.

| Variable | Description |
|---------|---------|
| rpcPort | Port for remote procedure calls to the node |

* `statsdBuildConfig` is the config section for the server to collect metrics. 

| Variable | Description |
|---------|---------|
| host | IP of the stat server; you can write yours if you have one up and running |
| port | Port of the server to send the data to |


* `bootNodeList` is the variable for the Boot Node to address when you enter the network the first time or after a while. `1` stands for the ID of the Boot Node, `172,17,0,2` - for the IP address Boot Node resides at (Docker's default IP address in this case). `1667` - port Boot Node receives requests to.

* `poaPort` is the variable for communication with PoA Nodes (receiving requests for transactions, sending transactions, receiving microblocks. 

* `logsBuildConfig` is the config section for the log server.

| Variable | Description |
|---------|---------|
| host | IP of the log server; you can write yours if you have one up and running |
| port | Port of the server to send the data to |

* `extConnectPort` is the variable that defines the port for commnunicating with the outer world (e.g. broadcasting). 

## Use Cases

#### Creating the initial identifying public key.

To start operating as a simple node in the network, you'd run the first four initialiation commands (cf. "Initialization of a simple node") then you'd run `-K` to create your initial public key identifying you in the network. To this public key you can receive transactions as well as generate and send them from this public key.


#### Creating a second public key.

You can create a large number of public keys for a single node. Let's say you want to generate and use a second public key as the address to (one of) your wallet(s). In this case , you'd run the initial four commands to initialize a node (cf. "Initialization of a simple node"), then run `-K ` to create your initial public key and then run `-K` again to create a second public key intended to be used as your wallet address (for this node). Then you'd be able to run send and receive payments form and to through the second public address using it a wallet.


#### Checking your public keys

In the case you want to check the public keys you generated overtime, you'd run `--show-my-keys`.


#### Generating a transaction and sending it to another participant (public key)

After you've created enough public keys, you may want to act as an active member of the network and, say, send transactions.
To send a transaction, you'd need to run `-S amount:to:from:currency` where `amount` stands for the amount intended to be send, `to` stands for the public key of the receiver, `from` stands for your chosen public key, and `currency` stands for the currency intended to be used.\
Your transaction still needs to be validated before it reaches the receives, so it is automatically propagated to the pending pool. Then you'd wait till your transaction is validated, i.e. included in a block.


#### Generating a test transaction or unlimited number of test transactions

In the case you want to test this functionality, you'd run `-G qTx` where `qTx` stands for the chosen number of transactions or `-F` for an unlimited number of transactions and check the results.


#### Checking the balance of a public key

In the case you want to know the balance of a public key, you'd run `-B publicKey` where `publicKey` stands for the chosen public key.


## Testing

Launch a Boot Node or Simple Node.\
Execute `stack test`

### UML

```yuml:class
[code]-[note:code2]

```
