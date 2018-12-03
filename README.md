# Splunk Cowrie Getting Started Guide

## Installation and Dependencies
Deploying and configuring Cowrie is a straightforward process, and integrating it with Splunk is a cakewalk with our easy button. Just start an AWS Ubuntu 14.04 instance.

Run the following in the terminal:
```
wget -q https://raw.githubusercontent.com/d1vious/splunk_cowrie/master/easy_button.sh
sudo ./easy_button.sh -s <splunk server url> -t <splunk HEC auth token>
```

But if curious how it is built and modified read below:

#### Step 1. Install Dependencies
`sudo apt-get install git python-virtualenv libssl-dev libffi-dev build-essential libpython-dev python2.7-minimal authbind`

#### Step 2. Create a user account
```
$ sudo adduser --disabled-password cowrie
$ sudo su - cowrie
```

#### Step 3. Checkout code 
```
$ git clone http://github.com/cowrie/cowrie
$ cd cowrie
```

#### Step 4. [Virtual Environment](https://realpython.com/python-virtual-environments-a-primer/#what-is-a-virtual-environment) and requirements.txt

_Side note, we want to use a python virtual environment here mainly to isolate the OS local python environment from the dependencies we will install for cowrie._

```
$ pwd
/home/cowrie/cowrie
$ virtualenv --python=python2 cowrie-env
$ source cowrie-env/bin/activate
(cowrie-env) $ pip install --upgrade pip
(cowrie-env) $ pip install --upgrade -r requirements.txt
(cowrie-env) $ pip install splunk-sdk
```

#### Step 5. Copy configuration file from template 
For cowrie configuration file 
`$ cp etc/cowrie.cfg.dist etc/cowrie.cfg`

List of cowrie allowed username and password
`$ cp etc/userdb.example etc/userdb.txt`

We will come back to both of these


#### Step 6. Change listening port to 22
First change your ssh listening port to something other than port 22. Edit `/etc/ssh/sshd_config` change Port to something unique (example 5222) then restart the service `sudo service ssh restart`. Next time you access the machine you should be using 5222 or whatever you had configured here. 

Now let cowrie use port 22 via iptables redirect

`$ sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222`

## Configuration 
After the Splunk research team deployed their instance of Cowrie, the first thing we learned was that making it interesting to an attacker was as important as anything we would do with it. This meant making sure that the honeypot was configured to feel and look like the environment you are trying to mimic. In my case I was going for an Ubuntu 14.04 linux server. 

### cowrie.cfg
First we start by configuring the Cowrie service it self under `/home/cowrie/cowrie/etc/cowrie.cfg` from Step 5 above. 
You can see a **full configuration example** [here](cowrie.cfg), but let me highlight the more important toggles. 
* **hostname** - defaults to svr04, a dead give away this is a Cowrie instance, you want to change this. In our example we used __cloud-webnode34__
* **interactive\_timeout** - defaults to `180`, I increase it to `300` to make sure we do not disconnect potential attackers from a bad connection early.
* **kernel\_version** - critical that this is update to reflect the kernel you want to emulate, in our case the default one installed with Ubuntu 14.04 is `3.13.0-158-generic`
* **kernel\_build\_string** - same as above, each OS is slightly different, in our case `##208-Ubuntu SMP Fri Aug 24 17:07:38 UTC 2018` 
* **version** - SSH banner version to display for a connecting client, make sure this matches your OS’s, in our case for a default install is: `SSH-2.0-OpenSSH_6.6.1p1 Ubuntu-2ubuntu2.10`
* **listen\_endpoints** - because we updated our ssh settings so Cowrie can use port 22 for the honeypot we must configure it here, we set `tcp:22:interface=0.0.0.0`

If running on a cloud instance (GCP,AWS,Azure) modify the following:
* **fake\_addr** = <local instance address> eg. 172.30.xxx.xxx
* **internet\_facing_ip** = <public IP of instance> eg. 34.217.xxx.xxx

We will leave the output configuration as is for now as we will come back to it in a bit. Save and exit the config and let’s look over at the operating system now. 

### userdb.txt
`/home/cowrie/cowrie/etc/cowrie.cfg` from step 5 contains all the allowed username and password combinations/regex’s for the honeypot. You can see an example here. You will likely be updating this file consistently as you adjust your honeypot to capture new attacks. When we started running our instances we noticed many failed logins from username pi and random passwords which is associated with the default credentials for raspberry Pi. We adjusted our [userdb.txt](userdb.txt) to include `pi:x:*` and a few days later caught someone dropping this trojan which Tobias Olausson did a great breakdown of here.

### File system
The default cowrie filesystem is a for a Debian operating system, Cowrie creates a mapping of the OS file structure and stores it under `/home/cowrie/cowrie/share/cowrie/fs.pickle`.  You can create a mapping file from any OS via running the included tool createfs. We already created a mapping for ubuntu 14.04 via: 

`/home/cowrie/cowrie/bin/createfs -l /. -o/home/cowrie/cowrie/share/cowrie/ubuntu14.04.pickle -p`

Here we are telling the tool to use the source file system from the current machine (eg. `-l /.`) because the machine we are running cowrie in is also Ubuntu 14.04. Alternatively you can run the tool in a fresh install of the OS you are attempting to mimic. Or after you have added users, created directories, and basically mocked in a fresh install what you would like the honeypot to report. In any case you can alternatively download and use the one we created [here](ubuntu14.04.pickle). Notice that we are also emulating here all the folders/files under /proc as well with option (`-p`).

### txtcmd
Cowrie being a medium interaction honeypot it does not actually run a full operating system, but instead emulates one. As part of this most command outputs like mount and df are actually faked. We have to update the default outputs with more believable ones for a Ubuntu host running on AWS (in our case). In order to do this you can find and populate the respective commands out under the `/home/cowrie/cowrie/share/cowrie/txtcmds` directory. A few we updated for our instance were:

* `bin/dmesg` 
* `bin/mount`
* `bin/lscpu`
* `bin/df`
* `usr/bin/lscpu`

You can see their content [here](txtcmds).

## Output events to Splunk
The final configuration piece is where we want to output our events to our Splunk instance. Cowrie has a prebuilt output plugin for Splunk using the [HTTP event collector](http://dev.splunk.com/view/event-collector/SP-CAAAE6M) that writes the events in JSON which is automatically parsed. Here is an example of the configuration:

```
[output_splunk]
enabled = true
url = https://<splunk.instance.address.com>/services/collector/event
token = <HTTP Collector Token>
index = cowrie
sourcetype = cowrie
source = cowrie
```

It is mostly self explanatory, though you do need to create a HTTP event collection endpoint for Cowrie using these instructions. 

## Running and important directories/tools
To **start** running cowrie just run `/home/cowrie/cowrie/bin/cowrie start` under the cowrie user. You can look at `var/log/cowrie/cowrie.log` to see any error outputs in detail from running if you run into one. Also below is a list [source](http://docs.splunk.com/Documentation/Splunk/latest/Data/UsetheHTTPEventCollector#Configure_HTTP_Event_Collector_on_Splunk_Enterprise) of important tools/directories to be aware of when operating cowrie and why.

* `var/lib/cowrie/tty/` - session logs from attackers, they can be replayed using with the bin/playlog utility.
* `var/lib/cowrie/downloads/` - files transferred from the attacker to the honeypot are stored here
* `bin/playlog` - utility to replay session logs

There is an existing Splunk [app](https://splunkbase.splunk.com/app/2666/) available for log analysis 


