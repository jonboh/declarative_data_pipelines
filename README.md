# Declarative, Reproducible, Free and Open Source Data Pipelines
This repository is the accompanying material to a talk I gave to the students of
[Deusto's Digital Industry dual degree](https://www.deusto.es/es/inicio/estudia/estudios/grado/grado-dual-industria-digital).

In this talk we walk through the skeleton of a data pipeline configured using the
Nix language. We use a Nix Flake to define the system, this provides us with a completely
declarative and reproducible system.

The primary aim of the talk is to introduce to students the kinds of systems that they
will end up building to consume data in their professional career in a way that will
allow them to reproduce the system in their own hardware.

The system presented is not intended to represent a production ready environment but an
experimentation playground.


# Data pipeline sub-systems

## OPC Server
Representing the OT level of our pipeline we will deploy a very simple OPC Server
that will publish 3 variables that change with different frequencies.

## Telegraf Collector Agent
Reading from the OPC server we have a Telegraf agent that will write the values read
to InfluxDB and Kafka.

## InfluxDB
InfluxDB is a timeseries datatabase that will serve as our storage solution for the
values read and the computations derived from these values.

## Apache Kafka
A message broker to stream data to the model and its "predictions" back to the Database.

## Custom Rust Model
A very simple Rust binary that will be subscribed to the `opc` topic where the Collector Telegraf
agent will send all the OT data.
This model wil perform two computations and write them back to Kafka in the `model` topic.

## Telegraf Kafka Agent
This telegraf agent reads from the `model` topic and writes the values into the database.

## Grafana Dashboard
Finally we display all the series in a Grafana dashboard.


# Instructions
This guide assumes you are running this project in a Linux machine
(not necessarily a NixOS one).

Most commands are expected to be run from the root of this project.
```bash
git clone git@github.com:jonboh/declarative_data_pipelines.git
cd declarative_data_acquisition
# continue with the following steps
```

## Prepare the development environment
### Install Nix
Follow the [official instructions](https://nixos.org/download) and install the Nix
package manager.

### Activate Flake support
You can follow the [wiki's instructions](https://nixos.wiki/wiki/Flakes).
But in short, you need to write into `/etc/nix/nix.conf` the following content:
```
experimental-features = nix-command flakes
```

### Activate the development environment
Go to this projects' folder and run:
```bash
nix develop
```
Nix will download all the necessary development tools to run this project.
After that you can check that it has worked by running some of them, for example:
```
age --help
```
should result in the help of the `age` tool.

## Regenerate the secrets
To reproduce:
1. Generate a new age key:
```bash
age-keygen -o ./master-age.key
```
2. Add your key as the master key of the project in .sops.yaml:
```yaml
keys:
  - &master <your public age key here>
creation_rules:
  - path_regex: secrets/*
    key_groups:
    - age:
      - *master
```
If you open the .sops.yaml versioned in this repository you'll see that there's already
a public key, that's the public key of my age key, the one I used to reproduce this
configuration in my computer. As unencrypted keys should never be versioned and I haven't
shared the key with you, you need to create your own (previous step) and reencrypt
the token and password for InfluxDB (next step).

3. Generate a new token and password for InfluxDB
```bash
sops secrets/influxdb_token
```
This command will open your editor (configured value of $EDITOR).
Write in this file the content of the token that will be used by applications
that want to communicate with InfluxDB (Grafana and Telegraf).
For example:
```
devtoken
```
Now repeat the process to generate the password for the InfluxDB user. This password
will be used to log in the InfluxDB Portal.
```bash
sops secrets/influxdb_password
```
and write a password (it should be longer than 8 characters), for example:
```
devpassword
```

## Set the network device for communication between systems
Modify the `net_device` in `flake.nix`. You should set this to the network interface
in which the Raspberry Pi will be connected. Usually it will be  your main ethernet
network device.

## Add your ssh public key to the systems
Modify `common/configuration.nix` and add your key to the list of authorized ssh keys, for example:
```nix
  users.users.admin = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAninVG6bOxD7bOi7od3WJJvPAV7DEiejNqHXrRqzdKW jon.bosque.hernando@gmail.com"
      # you should put here your ssh public key.
    ];
  };
```
This will allow you to log into the admin user in each of the systems with through ssh.
Also it will allow you to remotely push configuration changes without the need to rebuild the virtualbox
and raspberry images.

## Build the systems
Just build the output packages of the flake:
```bash
nix build ".#opc@raspberry" --system aarch64-linux
# or if you are running everything on virtualbox:
nix build ".#opc@vbox"
```
```bash
nix build ".#collector@vbox"
```
```bash
nix build ".#db@vbox"
```
Each of these commands will generate a symlink `result` to the output of the build.
To deploy each of the systems you will need the image of each one, so, build one,
deploy it (next step) and then build the next one and repeat.


## Deploy the systems
### First Time
#### Raspberry
Burn the image into your sd card.

WARNING!: the following `dd` command will wipe any content in the location pointed to `of` (your sd card):
```
zstd -d result/sd-image/nixos-sd-image-23.11.20240228.c8e74c2-aarch64-linux.img.zst -o opc-rasp-image.img
dd if=opc-rasp-image.img of=/dev/<your_sdcard> bs=4M status=progress
sync
```
Remove the sdcard, insert it into the raspberry and boot it up. The raspberry should get
to the login screen in the TTY. At this point the OPC server will already be running.

You won't be able to log in into admin because a password is not set by default.
To enter the raspberry you need to use ssh into it. You don't need to do it though.

#### VirtualBox Images
Open VirtualBox and import the generated images.
Then start each of the images.

#### Deploying the Master key for secrets
Now you should have all the systems up and running, however they don't have the
master key to decrypt the secrets that we generated in the first steps. This means
that Grafana and the Telegraf collector won't be able to read and write into the DB.

In a production environment you would not need to do this step as you could use a KMS.
But we have to deploy the `master-age.key` ourselves.
Copy through ssh the master key into `collector@vbox` and `db@vbox`, and then reboot the system
so that secrets are decrypted and made available.
```bash
scp ./master-age.key admin@collector-vbox:
ssh collector-vbox "sudo reboot"
scp ./master-age.key admin@db-vbox:
ssh db-vbox "sudo reboot"
```
You will need to define in your `.ssh/config` those two ssh hosts:
```
Host db-vbox
   HostName 192.168.0.10
   User admin
   IdentityFile ~/.ssh/id_ed25519
   IdentitiesOnly yes

Host db-vbox
   HostName 192.168.0.10
   User admin
   IdentityFile ~/.ssh/id_ed25519
   IdentitiesOnly yes
```

### Changing Configurations
This section applies to both VirtualBox machines and raspberry ones.
If you have configured an ssh key in `common/configuration.nix` you can push
configuration changes through ssh with a command like this:
```bash
nixos-rebuild switch --flake ".#db@vbox" --target-host db-vbox --use-remote-sudo
```
Note that `db-box` in `--target-host` is an entry in my `.ssh/config`, as shown in the
previous step.

You can check that the configuration is correct by ssh-ing to the machine:
```bash
ssh db-vbox
```
This command should log you in the `db@vbox` machine. Running `hostname` there
should return `db-host`.

## Checking the working systems
At this point we are done, you can use the services that have been deployed or tweak their configurations.
Well done!

### Grafana Dashboard
Using your browser go to the address of Grafana, which runs in `db-host`, by default: `192.168.0.10:3000`.
Log in with the default admin user.
```
user: admin
password: admin
```
Go to Home->Dashboards->Sensor Dashboard
You should see for plots. The three top ones correspond to the OPC variables read by `ot-collector`
The forth one corresponds to the computations performed by the model running in `db-host`.

### Apache Kafka Topics
You can use kafkacat `kcat` command to listen to the two topics in Apache Kafka
To listen to the topic that receives the OT data (`opc` topic) run:
```bash
kcat -b 192.168.0.10:9092 -t opc -C
```
To listen to the topic that receives the model computations (`model` topic) run:
```bash
kcat -b 192.168.0.10:9092 -t model -C
```

### InfluxDB
Using your browser go to the address of InfluxDB, which runs in `db-host`, by default: `192.168.0.10:8086`.
Log in with `devuser`:
```
user: devuser
password: <whatever you set on secrets/influxdb_password>
```
