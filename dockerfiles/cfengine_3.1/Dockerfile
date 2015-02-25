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

FROM ubuntu:12.04
MAINTAINER Matthew Rahtz

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update
# netcat needed for hack in post-receive hook to prompt
# cf-serverd to re-evaulate promises
RUN apt-get --yes install wget openssh-server git supervisor cfengine3 netcat

# https://docs.docker.com/articles/using_supervisord/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN mkdir -p /var/log/supervisor

RUN mkdir /var/lib/cfengine3/masterfiles
# init_policy contains some minimal CFEngine policy for the
# first startup of cf-serverd -  just enough to allow clients
# to connect and update
# (cf-serverd should notice once masterfiles have changed, though,
#  and reload - so this really is only used for the initial startup)
COPY init_policy/* /var/lib/cfengine3/inputs/
COPY init_policy/* /var/lib/cfengine3/masterfiles/
# cf-serverd won't start if the permissions are too relaxed
RUN chmod 600 -R /var/lib/cfengine3 /var/lib/cfengine3/masterfiles
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
