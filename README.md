A collection of scripts for spawning CFEngine policy servers
using Docker containers from branches of a CFEngine Git repository.
Creates a separate policy server for each branch pushed to the remote
repository for easy testing of development branches.

Scripts are provided for both CFEngine 3.1 and 3.6.

![Demo](/demo.gif?raw=true)

## Files

* `dockerfiles` contains the Dockerfiles used to create the Docker
  images which serve as the policy server containers.
* `post-receive.sample.3.1` and `post-receive.sample.3.6` are sample
  Git post-receive hooks which control the whole process.
* `dhcp_container.sh` is a script for creating a container with
  an interface brought up with DHCP, so appearing on the network as if it
  were just another server.
* `cfengine_container.sh` does the hard work of creating the container
  and pushing the appropriate Git branch to it.
* `vagrant_test_3.1` and `vagrant_test_3.6` are folders for use with
  Vagrant which show off the system as a whole and do a basic
  set of tests.

## Usage

### Prerequisites

The intended setup involves two servers: one running your production CFEngine
policy server, holding your master Git repository, and another for development
work, where the containers are created.

On the development server, we need:
* Docker
* A bridge interface (`br0` by default) on the server housing your
  development CFEngine Git repository
* `brctl` for managing bridges (from package `bridge-utils` in Debian/Ubuntu)
* `nsenter` for setting up a DHCP client within the container
 * See https://github.com/jpetazzo/nsenter
* `dhcpcd`

More generally in the network infrastructure, we need:
* A DHCP/DNS server capable of doing Dynamic DNS (so that hosts configured
  using DHCP will have a DNS name created based on their stated hostname)
  * Strictly speaking, not needed, but makes the process a lot friendlier

### Setup

* On the development server, create a bare Git repository to be used as
  as a Git remote for development work. Place the entire checkout folder
  in the repository's hooks folder.
```bash
$ git init --bare /var/cfengine_git
$ cd /var/cfengine_git/hooks
$ git clone https://github.com/mrahtz/docker-cfengine-servers
```
* Depending on whether you use CFEngine 3.1 or 3.6, adapt either
  `post-receive.sample.3.1` or `post-receive.sample.3.6` into your
  repository's `post-receive` hook. Tweak the `CONTAINER_HOSTNAME_PREFIX` at the top
  to control what names your policy servers will appear with.

  If you don't already have a `post-receive` hook, the samples can be used as-is:
```bash
$ cp docker-cfengine-servers/post-receive.sample.3.6 post-receive
```
* Optionally, customise the `post-receive` hook used by the container to
  update server policy. These are located in
  `dockerfiles/<version>/post_receive_hook`. Customisation may be necessary
  if your versioned configuration includes directories other than `masterfiles`.
* Build the Docker images with:
```bash
$ cd docker-cfengine-servers/dockerfiles
$ ./build_images.sh
```

### Creating Containers

* Add a Git remote for your development server repository to your local
  configuration checkout:
```bash
$ cd ~/cfengine
$ git remote add dev root@<dev server>:/var/cfengine_git
```
* Push a branch to the development remote to spawn the container. A CFEngine
policy server will appear at "`$CONTAINER_HOSTNAME_PREFIX-<branch name>`"
serving the contents of your branch:
```bash
$ git checkout -b addsparkles
...
$ git push dev addsparkles
...
remote: Creating docker container with name 'cfe36srv-addsparkles' from image 'mrahtz/cfe36srv'...
...
$ sudo cf-agent --bootstrap cfe36srv-addsparkles
$ sudo cf-agent -K
# sparkles!
```

## Example Setup

For an example of how the whole thing fits together, see the `vagrant_test*`
directories. `vagrant up` as usual, and a VM will execute a set of checks
demonstrating how everything works.

## Design Notes

* Communication with containers is done using SSH keys, generated when building
  the Docker images. The same SSH key is used for all containers created.
  * If you need access to the containers for debugging, use `container_ssh.sh`.
* Keys for the CFEngine server are generated during image build, and are
  therefore the same for all containers created.
