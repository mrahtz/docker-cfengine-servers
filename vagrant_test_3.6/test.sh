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

# Tests functionality of Git hooks and policy server containers

set -o errexit

cd /home/vagrant/cfengine

# create a branch for modifications
git checkout -b change1
# change something
sed -i '1 s/.*/# foo/' masterfiles/def.cf
git commit -am 'Dummy commit'
# push branch to remote to spawn test policy server
git push dev change1

git checkout -b change2
cp /repo/vagrant_test_3.6/hello_world.cf masterfiles/
git add masterfiles/hello_world.cf
# insert 'hello_world' at end of bundlesequence
sed -i '/bundlesequence =>/,/};/s/};/hello_world,\n};/' masterfiles/promises.cf
# insert 'hello_world.cf' at end of inputs
sed -i '/inputs =>/,/};/s/};/"hello_world.cf",\n};/' masterfiles/promises.cf
git add masterfiles/promises.cf
git commit -m 'Add "hello_world" promise'
git push dev change2

cf-agent --bootstrap cf36srv-change2
cf-agent -K
if [[ $(cat /tmp/hello.txt) != "Hello, world!" ]]; then
    echo "Error: /tmp/hello.txt not as expected" >&2
    exit 1
fi

sed -i 's/hello.txt/hello2.txt/' masterfiles/hello_world.cf
git commit -am 'Modify hello_world'
git push dev change2
cf-agent -Kf update.cf
cf-agent -K
if [[ $(cat /tmp/hello2.txt) != "Hello, world!" ]]; then
    echo "Error: /tmp/hello2.txt not as expected" >&2
    exit 1
fi

echo "Tests passed! :)"
