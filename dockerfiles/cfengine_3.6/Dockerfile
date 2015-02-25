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

FROM ubuntu:14.04
MAINTAINER Matthew Rahtz

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update
RUN apt-get --yes install wget openssh-server git supervisor

# https://docs.docker.com/articles/using_supervisord/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN mkdir -p /var/log/supervisor

RUN wget --quiet https://s3.amazonaws.com/cfengine.package-repos/community_binaries/cfengine-community_3.6.1-1_amd64.deb
RUN dpkg -i cfengine-community_3.6.1-1_amd64.deb

# manually bootstrap using the default policy - just enough to get
# cf-serverd up
# (we don't use cf-agent --bootstrap because we have no stable
#  address to bootstrap do)
RUN cp -a /var/cfengine/masterfiles/* /var/cfengine/inputs/
RUN mkdir /var/cfengine_git
RUN GIT_DIR=/var/cfengine_git git --bare init
COPY post-receive-hook /var/cfengine_git/hooks/post-receive

RUN mkdir /var/run/sshd
RUN mkdir /root/.ssh
# otherwise root login fails with exit status 254
RUN sed -i 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config
# otherwise login will take a long time if there are issues with DNS
RUN echo 'UseDNS no' >> /etc/ssh/sshd_config
ADD container_ssh_key.pub /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys

CMD ["/usr/bin/supervisord"]
