#!/bin/bash

################################################################################
# Copyright (c) 2014, 2015 Genome Research Ltd.
#
# Author: Matthew Rahtz <matthew.rahtz@sanger.ac.uk>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
################################################################################

# Sets up Git repositories

set -o errexit

git config --global user.name foo
git config --global user.email foo@bar.com

# create an 'origin' Git repository for CFEngine configuration
rm -rf /var/cfengine_git
git init --bare /var/cfengine_git
# add CFEngine masterfiles to Git repository
cd /var/cfengine
rm -rf .git
git init
git add masterfiles
git commit -m 'Initial commit'
git remote add origin /var/cfengine_git
git push origin master

# set up a 'dev' clone, hooked to create the test servers
# (normally this would be on a separate server)
rm -rf /var/cfengine_git_dev
git clone --bare /var/cfengine_git /var/cfengine_git_dev
cd /var/cfengine_git_dev/hooks
cp -r /repo docker-cfengine-servers
cp docker-cfengine-servers/post-receive.sample.3.6 post-receive

# get a local clone, linked to both repositories
rm -rf /home/vagrant/cfengine
git clone /var/cfengine_git /home/vagrant/cfengine
cd /home/vagrant/cfengine
git remote add dev /var/cfengine_git_dev
