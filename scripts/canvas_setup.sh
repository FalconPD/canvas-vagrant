#!/bin/bash

# Based on: https://github.com/instructure/canvas-lms/wiki/Production-Start

set -e # Exit script immediately on first error.
set -x # Print commands and their arguments as they are executed.

LOWMEM=yes # tweeks for a low memory build environment
VAGRANT_BASE="/vagrant" # useful if you are running this script from somewhere else

############### Setup repositories, keys, and install pacakges #####@##########
if [ -f $VAGRANT_BASE/packages/apt-cache.tar ]; then # keeps us from having to download packages over and over
	sudo tar xvf $VAGRANT_BASE/packages/apt-cache.tar -C /var/cache/apt/archives
fi
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:brightbox/ruby-ng
sudo add-apt-repository -y "deb https://dl.yarnpkg.com/debian/ stable main"
sudo add-apt-repository -y "deb https://oss-binaries.phusionpassenger.com/apt/passenger trusty main"
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7
curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash - # will automatically apt-get update
sudo apt-get -y install ruby2.4 ruby2.4-dev zlib1g-dev libxml2-dev libsqlite3-dev \
	postgresql libpq-dev libxmlsec1-dev curl make g++ git yarn=1.3.2-1 nodejs \
	build-essential swapspace nginx-extras passenger unzip redis-server \
	jq python3-pip

############################# Setup Postgres ##################################
sudo -u postgres createuser $USER
sudo -u postgres psql -c "alter user $USER with superuser" postgres
createdb canvas_production

############################# Setup canvas ####################################
SECRETS="$VAGRANT_BASE/config/secrets.json"
export HOSTNAME=vagrant-ubuntu-trusty-64
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ssl-cert-snakeoil.pem
export CANVAS_LMS_ADMIN_EMAIL=`cat $SECRETS | jq -r ".email"`
export CANVAS_LMS_ADMIN_PASSWORD=`cat $SECRETS | jq -r ".password"`
export CANVAS_LMS_STATS_COLLECTION="opt_in"
export CANVAS_LMS_ACCOUNT_NAME="Monroe Township Schools"
export RAILS_ENV="production"
if [ -n "$LOWMEM" ]; then
	export CANVAS_BUILD_CONCURRENCY=1
	export DISABLE_HAPPYPACK=1
	export JS_BUILD_NO_UGLIFY=1
fi

cd
CANVAS_FILE=$VAGRANT_BASE/packages/canvas-lms-stable.zip
if [ -f "$CANVAS_FILE" ]; then
	unzip $CANVAS_FILE
	mv canvas-lms-stable canvas-lms
else
	git clone https://github.com/instructure/canvas-lms.git
fi
cd canvas-lms
if [ -n "$LOWMEM" ]; then
	sed -i -r "s/(max_old_space_size=)([0-9]+)/\11000/" package.json
fi
sudo gem install bundler --version 1.13.6
bundle install --path vendor/bundle
yarn install
cp $VAGRANT_BASE/config/canvas/* config/
TOKEN=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 40 | head -n 1`
sed -i -r "s/(encryption_key: )(.*)/\1$TOKEN/" config/security.yml
mkdir -p public/assets app/stylesheets/brandable_css_brands
touch app/stylesheets/_brandable_variables_defaults_autogenerated.scss
#mkdir -p log tmp/pids public/assets app/stylesheets/brandable_css_brands
#touch app/stylesheets/_brandable_variables_defaults_autogenerated.scss
#touch Gemfile.lock
#touch log/production.log
#yarn install
bundle exec rake canvas:compile_assets
set +e # this is to get past the ExclusiveLock error
bundle exec rake db:initial_setup
set -e
bundle exec rake db:initial_setup
bundle exec rake brand_configs:generate_and_upload_all

# startup the background process
sudo ln -s ~/canvas-lms/script/canvas_init /etc/init.d/canvas_init
sudo update-rc.d canvas_init defaults
sudo /etc/init.d/canvas_init start

########################## Setup passenger and nginx ##########################
sudo cp $VAGRANT_BASE/config/nginx/nginx.conf /etc/nginx/
sudo cp $VAGRANT_BASE/config/nginx/sites-enabled/canvas.conf /etc/nginx/sites-enabled/
sudo service nginx restart

########################## Setup the local system #############################
cp $VAGRANT_BASE/config/vimrc ~/.vimrc
sudo pip3 install click
echo "Setting up timezone, allowing sis imports, and generating token..."
TOKEN=`bundle exec rails runner $VAGRANT_BASE/scripts/canvas_setup.rb`
cat $SECRETS | sed -r "s/(\"token\":[ ]*)\"(.*)\"/\1\"$TOKEN\"/" > ~/secrets.json
echo "Adding microsoft as auth provider..."
$VAGRANT_BASE/scripts/canvas_cli.py --server https://$HOSTNAME $SECRETS auth add microsoft
echo "Uploading SIS information..."
$VAGRANT_BASE/scripts/canvas_cli.py --server https://$HOSTNAME $SECRETS sis import $VAGRANT_BASE/config/genesis/genesis_upload.zip 
