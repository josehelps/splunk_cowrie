#!/bin/bash
usage() { echo "$0 usage:" && grep " .)\ #" $0;
echo "Example: sudo ./easy_button.sh -s https://my.splunkinstance.com:8088/services/collector/event -t affc3f0d-3bf7-55cc-940a-27aa7b4feaf4"
echo "Description: easy_button builds a cowrie instance that mimics an Ubuntu 14.04 server.
      If curious about the specific build steps we automate see: https://github.com/d1vious/splunk_cowrie";
exit 0; }
[ $# -eq 0 ] && usage
while getopts ":hs:t:" arg; do
  case $arg in
    t) # Specify splunk token value.
      SPLUNK_TOKEN=${OPTARG}
      ;;
    s) # Specify splunk instance
      SPLUNK_HOST=${OPTARG}
      ;;
    h | *) # Display help.
      usage
      exit 0
      ;;
  esac
done

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
   usage
   exit 0
fi

COWRIE_HOME="/home/cowrie"

# install deps
function install_deps {
	apt-get -qqy update
	apt-get -qqy install -y git python-virtualenv libssl-dev libffi-dev build-essential libpython-dev python2.7-minimal authbind
}
function create_users {
	# create users
	adduser --quiet --home $COWRIE_HOME --gecos '' --disabled-password cowrie
}
function build {
	# grab latest cowrie build
	su cowrie -c 'cd $COWRIE_HOME; \
		git clone --quiet http://github.com/cowrie/cowrie; \
		cd cowrie; \
		virtualenv --python=python2 cowrie-env --quiet; \
		source cowrie-env/bin/activate; \
		pip install --upgrade pip --quiet; \
		pip install --upgrade -r requirements.txt --quiet; \
		pip install splunk-sdk --quiet'
}

function configure {
	# grab our configuration and copy our configs
	su cowrie -c 'cd /home/cowrie/cowrie; \
		git clone -q https://github.com/d1vious/splunk_cowrie.git; \
		cp splunk_cowrie/cowrie.cfg etc/cowrie.cfg 2>/dev/null; \
		cp splunk_cowrie/userdb.txt etc/userdb.txt 2>/dev/null; \
		cp splunk_cowrie/ubuntu14.04.pickle share/cowrie/fs.pickle 2>/dev/null; \
		cp -R splunk_cowrie/txtcmds share/cowrie/txtcmds 2>/dev/null'
}

function generatehostname {
	# generate server name
	declare -a CATEGORIES=("webnode" "cmsservice" "cloudnode" "dnsservice" "api" "web" "cms" "ticket" "instance")
	ID=`echo $RANDOM | tr '[0-9]' '[a-zA-Z]'`
	NUMBER=$(echo $(( RANDOM % (10 - 5 + 1 ) + 5 )))
	SELECTEDCATEGORIES=${CATEGORIES[$RANDOM % ${#CATEGORIES[@]} ]}
	HOSTNAME="$SELECTEDCATEGORIES-$ID-$NUMBER"
	# set hostname
}

function switchssh {
    touch /etc/authbind/byport/22
    chown cowrie:cowrie /etc/authbind/byport/22
    chmod 770 /etc/authbind/byport/22
    PORT=$(echo 9$RANDOM | cut -c1-4)
    sed -i -e "s/#Port 22/Port $PORT/g" /etc/ssh/sshd_config
    echo "\n!!!Warning SSH port has been changed to: $PORT!!!"
    echo "!Next time logging in use this port (eg.. ssh -p $PORT <user>@<host>!"
    echo "!Or set your own port in /etc/ssh/sshd_config. Do not forgot to update your Firewall!\n"
    service ssh restart
    sed -i -e "s/AUTHBIND_ENABLED=no/AUTHBIND_ENABLED=yes/g" $COWRIE_HOME/cowrie/bin/cowrie
}

# MAIN
echo "### Starting Cowrie Configuration ###"
echo "Installing dependencies       (00%)"
install_deps

echo "Creating cowrie user          (33%)"
create_users

echo "Building cowrie               (44%)"
build

echo "Copying Ubuntu 14.04 Template (75%)"
configure

echo "Setting config parameters     (85%)"
generatehostname
sed -i -e 's/<configured_hostname>/$HOSTNAME/g' $COWRIE_HOME/cowrie/etc/cowrie.cfg
sed -i -e 's/<configured_splunk_server>/$SPLUNK_HOST/g' $COWRIE_HOME/cowrie/etc/cowrie.cfg

echo "Switching ssh		    (95%)"
switchssh

echo "### Completed (100%)###"