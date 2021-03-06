SHELL := /bin/bash # Use bash syntax

# Customise the dev server port
# ===
ifeq ($(PORT),)
	PORT=8099  # Default port for the dev server
endif

# Help text
# ===

define HELP_TEXT

Basic usage
===

> make setup    # Install dependencies
> make develop  # Run watch-sass and dev-server

Now browse to http://0.0.0.0:8007 to run the site

All commands
===

To understand commands in more details, simply read the Makefile

> make help                  # Print this help
> make develop               # (or `make it so`) `watch-sass` & `dev-server`
> make setup                 # `install-dependencies` & `update-env`
> make dev-server            # Run the Django server in the python virtualenv
> make sass                  # Compile all SASS files to CSS
> make watch-sass            # Background - watch SASS files, auto-compile to CSS on changes
> make update-env            # Update python dependencies in the python virtualenv
> make create-env            # Create a python virtualenv in the "env" folder
> make install-requirements  # Install pip requirements into virtualenv
> make install-dependencies  # Install system dependencies
> make apt-dependencies      # Install system dependencies for debian-based OSs
> make brew-dependencies     # Install system dependencies for MacOS
> make clean                 # Delete any extraneous files that have been created for development
> make dokku-start           # `sass` & `run gunicorn` - for dokku to run
> make run-gunicorn          # Run the webapp with gunicorn
> make rebuild-pip-cache     # To update the PIP_CACHE_REPO with pip requirements
> make pip-cache             # Pull down the PIP_CACHE_REPO into pip-cache dir

endef

# Variables
##

ENVPATH=${VIRTUAL_ENV}
ifeq ($(ENVPATH),)
	ENVPATH=env
endif
VEX=vex --path ${ENVPATH}



##
# Print help text
##
help:
	$(info ${HELP_TEXT})

##
# Auto-compile sass and start the development server
##
develop: watch-sass dev-server

##
# Prepare the project
##
setup: install-dependencies update-env

##
# Run the Django development server
##
dev-server:
	${VEX} ./manage.py runserver_plus 0.0.0.0:${PORT}

##
# Pull and build docs from maas-docs repo
##
docs:
	@echo "- Creating tmp/ directory"
	mkdir -p tmp

	@echo "- Updating maas-docs repository"
	if [ -d tmp/maas-docs ]; then cd tmp/maas-docs && git fetch origin && git reset --hard origin/master && git clean -fd; fi
	if [ ! -d tmp/maas-docs ]; then git clone git@github.com:canonicalltd/maas-docs.git tmp/maas-docs; fi

	@echo "- Remove all existing built docs and media files"
	find static/docs/* ! -name 'README.md' -type f -exec rm -rf {} +
	find templates/docs/* ! -name 'README.md' -type f -exec rm -rf {} +

	@echo "- Substitute our own base.tpl"
	cp config/docs-base.tpl tmp/maas-docs/src/base.tpl

	@echo "- Replace '../media' links with '/static/docs'"
	find tmp/maas-docs/src/en -name '*.md' -exec sed -Ei -e "s~(\.\./|\./)+media/~/static/docs/~" {} \;

	@echo "- Replace relative page links with '/docs/{page}'"
	find tmp/maas-docs/src/en -name '*.md' -exec sed -Ei -e "s~\]\((.?./|/docs/)*([a-zA-Z][\.a-zA-Z/-]+).html~](/docs/\2~" {} \;

	@echo "- Fix links in navigation"
	sed -Ei -e "s|href=\" *([a-zA-Z0-9-]+).html|href=\"/docs/\1|" tmp/maas-docs/src/navigation.tpl
	sed -Ei -e "s|href=\"http|class="external" href=\"http|" tmp/maas-docs/src/navigation.tpl

	@echo "- Remove classes from navigation"
	sed -Ei -e 's/class="[^"]+"//' tmp/maas-docs/src/navigation.tpl
	sed -Ei -e 's~intro-about-maas.html~/docs/~' tmp/maas-docs/src/navigation.tpl

	@echo "- Create landing page"
	if [ ! -e tmp/maas-docs/src/en/index.md ] && [ -e tmp/maas-docs/src/en/intro-about-maas.md ]; then \
		mv tmp/maas-docs/src/en/intro-about-maas.md tmp/maas-docs/src/en/index.md; \
		find tmp/maas-docs/src -name '*.md' -o -name '*.tpl' -exec sed -Ei -e "s~/docs/intro-about-maas/?~/docs/~" {} \; ; \
	fi

	@echo "- Build the docs templates"
	sh -c "python3 -m venv tmp/docs-env; . tmp/docs-env/bin/activate; pip3 install -r tmp/maas-docs/requirements.txt; make -C tmp/maas-docs build"

	@echo "- Copy templates to templates/docs"
	cp -r tmp/maas-docs/htmldocs/en/* templates/docs/.

	@echo "- Copy media to static/docs"
	cp -r tmp/maas-docs/media/* static/docs/.

	@echo "- Copy navigation to /docs/_navigation.html"
	cp tmp/maas-docs/src/navigation.tpl templates/includes/docs_navigation.html

##
# Build SASS
##
sass:
	sass --style compressed --update static/css

##
# Run SASS watcher
# - Runs in the background
# - Auto-compiles SASS files to CSS on changes
##
watch-sass:
	sass --debug-info --watch static/css &

##
# Get virtualenv ready
##
update-env:
	${MAKE} create-env

	${VEX} ${MAKE} install-requirements

##
# Make virtualenv directory if it doesn't exist and we're not in an env
##
create-env:
	if [ ! -d ${ENVPATH} ]; then virtualenv ${ENVPATH}; fi

##
# Install pip requirements
# Only if inside a virtualenv
##
install-requirements:
	if [ "${VIRTUAL_ENV}" ]; then pip install --exists-action=w -r requirements/dev.txt; fi

##
# Install required system dependencies
##
install-dependencies:
	if [ $$(command -v apt-get) ]; then ${MAKE} apt-dependencies; fi
	if [ $$(command -v brew) ]; then ${MAKE} brew-dependencies; fi

	if [ ! $$(command -v virtualenv) ]; then sudo pip install virtualenv; fi
	if [ ! $$(command -v vex) ]; then sudo pip install vex; fi

## Install dependencies with apt
apt-dependencies:
	if [ ! $$(command -v pip) ]; then sudo apt-get install python-pip; fi
	if [ ! $$(command -v sass) ]; then sudo apt-get install ruby-sass; fi

## Install dependencies with brew
brew-dependencies:
	if [ ! $$(command -v pip) ]; then sudo easy_install pip; fi
	if [ ! $$(command -v sass) ]; then sudo gem install sass; fi

##
# Delete any generated files
##
clean:
	rm -rf env .sass-cache
	find static/css -name '*.css*' -exec rm {} +  # Remove any .css files - should only be .sass files

##
# For dokku - build sass and run gunicorn
##
dokku-start: sass run-gunicorn

##
# Run the gunicorn app
##
run-gunicorn:
	gunicorn webapp.wsgi

# Production targets
# ===

# When creating a  new app, set where you want dependencies to be stored
# PIP_CACHE_REPO=lp:~webteam-backend/example-project/dependencies

##
# Update the pip requirements cache repository
##
rebuild-pip-cache:
	@if [ ! "${PIP_CACHE_REPO}" ]; then \
	    echo "PIP_CACHE_REPO not set, exiting"; \
	    exit 1; \
	fi

	rm -rf pip-cache
	mkdir pip-cache
	cd pip-cache && bzr init
	bzr branch ${PIP_CACHE_REPO} pip-cache
	pip install --exists-action=w --download pip-cache/ -r requirements/standard.txt
	cd pip-cache && bzr add .
	bzr commit pip-cache/ -m 'automatically updated requirements'
	bzr push --directory pip-cache ${PIP_CACHE_REPO}
	rm -rf pip-cache src

##
# Create the pip-cache from the PIP_CACHE_REPO
##
pip-cache:
	@if [ ! "${PIP_CACHE_REPO}" ]; then \
	    echo "PIP_CACHE_REPO not set, exiting"; \
	    exit 1; \
	fi

	bzr branch ${PIP_CACHE_REPO} pip-cache

# "make it so"
# ===

# The below targets
# are just there to allow you to type "make it so"
# as a replacement for "make develop"
# - Thanks to https://directory.canonical.com/list/ircnick/deadlight/

it: sass

so: develop

.PHONY: help develop setup dev-server sass watch-sass update-env
