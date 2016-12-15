# docker-pgrepl

This Dockerfile uses the standard postgres 9.4 docker image and adds a script that sets up streaming repliaction between two or more docker containers running PostgreSQL.

This is based off the work by @mgudmund at https://github.com/mgudmund/docker-pgrepl. It has been modified to better support use on DC/OS with persistent volumes, via:
* better support for re-entrant containers
* more environment variable support
* more flexible PGDATA placement
In addition, there are utility scripts for deployment and management on: 
* docker
* DC/OS (Marathon)

Additionally, the image has been customized to bootstrap the databases necessary for the gestalt-framework; this can be disabled by removing the gestalt.sh script.

---

# Usage under local docker

To clone this git repo run:

    # git clone https://github.com/GalacticFog/docker-pgrepl.git

To build the docker image do:

    # docker build -t postgres_repl .

To create the first docker container with the primary node run:

    # docker run -d -P --name pgrepl1  postgres_repl 

Check the logs to see if postgres started correctly:

    # docker logs pgrepl1
    ...
    LOG:  database system was shut down at 2015-06-30 08:14:39 UTC
    LOG:  MultiXact member wraparound protections are now enabled
    LOG:  database system is ready to accept connections
    LOG:  autovacuum launcher started
    

To add a standby to the primary, pgrepl1, run:

    # docker run -d --link pgrepl1:postgres -P --name pgrepl2 -e PGREPL_ROLE=STANDBY  postgres_repl

Check the logs to make sure it has entered standby mode:

    # docker logs pgrepl2 
    ...
    LOG:  database system was interrupted while in recovery at log time 2015-06-30 08:15:14 UTC
    HINT:  If this has occurred more than once some data might be corrupted and you might need to choose an earlier recovery target.
    LOG:  entering standby mode
    LOG:  started streaming WAL from primary at 0/4000000 on timeline 1
    LOG:  redo starts at 0/4000060
    LOG:  consistent recovery state reached at 0/5000000
    LOG:  database system is ready to accept read only connections
    
To add a second standby to the primary, pgrepl1, run:

    # docker run -d --link pgrepl1:postgres -P --name pgrepl3 -e PGREPL_ROLE=STANDBY  postgres_repl

To add a third standby, downstream of the first standby, pgrepl2, run:

    # docker run -d --link pgrepl2:postgres -P --name pgrepl4 -e PGREPL_ROLE=STANDBY  postgres_repl

The --link directive specifies what upstream postgres node to connect the standby to. 
After the above commands have been run, you should have a Postgres streaming replica setup like this:
<pre>
pgrepl1 
   |      
   |--> pgrepl2 --> pgrepl4
   |
   |--> pgrepl3
</pre>
To promote a standby to become a primary, you can use docker exec. Example:

If pgrepl1 crashes, run the following command to promote pgrepl2 to become the primary
  
    # docker exec pgrepl2 gosu postgres pg_ctl promote
    server promoting

Check the logs to see if has promoted successfully:

    # docker logs pgrepl2
    ...
    LOG:  received promote request
    FATAL:  terminating walreceiver process due to administrator command
    LOG:  record with zero length at 0/5000060
    LOG:  redo done at 0/5000028
    LOG:  selected new timeline ID: 2
    LOG:  archive recovery complete
    LOG:  MultiXact member wraparound protections are now enabled
    LOG:  database system is ready to accept connections
    LOG:  autovacuum launcher started
        

This would promte pgrepl2 to be the primary. The downstream standby from pgrepl2, pgrepl4 will switch timelines and continue to be the downstream standby. 
Checking the logs for pgrepl4 will show that:

    # docker logs pgrepl4
    LOG:  replication terminated by primary server
    DETAIL:  End of WAL reached on timeline 1 at 0/5000060.
    LOG:  fetching timeline history file for timeline 2 from primary server
    LOG:  new target timeline is 2
    LOG:  record with zero length at 0/5000060
    LOG:  restarted WAL streaming at 0/5000000 on timeline 2

pgrepl3 would in this case not have any primary to connect to. You could reconfigure it to follow pgrepl2, or just remove it and create a new standby, downstream from pgrepl2.

If you don't want to use the docker --link, you can specify the IP and port of the replication primary using PGREPL_MASTER_IP and PGREPL_MASTER_PORT as environment variables in your docker run command.

There are example scripts in the [docker](/docker) directory that perform these operations, using container linking:

    # ./docker/primary.sh pgrepl1
    Container ID: 0b0fb5dec403c81b9cca514473ea54c9189bd3f205ce6cf53923e5ee4fac488f
    # ./docker/standby.sh pgrepl1 pgrepl2
    Container ID: e94b7c5359b3af2ac7f9afe42841453e2bc18bd73770fb5d0fd9bc642e20f25e
    # ./docker/standby.sh pgrepl1 pgrepl3
    Container ID: d64e3020efdf4402bd41ed586a12cb60fecdc788f4829506a08acf19c9f95f79
    # ./docker/standby.sh pgrepl2 pgrepl4
    Container ID: 4a49008b507b3c25c6d59c7e8bcde65c8d89d4422d26417e99ead459a1ba7961
    # ./docker kill pgrepl1
    pgrepl1
    # ./docker/promote.sh pgrepl2
    server promoting
    # docker logs pgrepl4 
    LOG:  replication terminated by primary server
    DETAIL:  End of WAL reached on timeline 1 at 0/3000060.
    LOG:  fetching timeline history file for timeline 2 from primary server
    LOG:  new target timeline is 2
    LOG:  record with zero length at 0/3000060
    LOG:  restarted WAL streaming at 0/3000000 on timeline 2

# Usage under DC/OS

The image supports usage under [DC/OS](https://dcos.io/) (1.8 or later), deployed via [Marathon](https://mesosphere.github.io/marathon/). 
The [marathon](/docker) directory constains scripts to deploy primary and standby containers and to promote standby containers to primary operation:
* All containers are provisioned using [local persistent volumes](https://mesosphere.github.io/marathon/docs/persistent-volumes.html). This has the effect of locking the container
  to a specific host, but it means that if the container is restarted (after being suspended or crashing), the PGDATA directory is still available.
* All containers are provisioned with a [virtual IP](https://dcos.io/docs/1.8/usage/service-discovery/load-balancing-vips/virtual-ip-addresses) (VIP). 
  The promote script has the option to modify the VIP when moving a container from standby, allowing it to take over the VIP of the primary. This means that there
  is no need to update the configuration of downstream services (including other standbys).

Assuming that Marathon is available at http://marathon.mesos:8080, to create a primary with Marathon application ID pgrepl1 and VIP `primary.pgrepl`, run: 
    
    # ./marathon/primary.sh http://marathon.mesos:8080 pgrepl1 /primary.pgrepl:5432

At this point, applications can access the primary at the URL: 

    primary.pgrepl.marathon.l4lb.thisdcos.directory:5432

Creating a standby against this primary can be done as follows: 
 
    # ./marathon/standby.sh http://marathon.mesos:8080 pgrepl1 pgrepl2 /standby.pgrepl:5432

The pgrepl2 standby is configured to reach the primary using the URL above, and is itself available (for read-only access) at: 

    standby.pgrepl.marathon.l4lb.thisdcos.directory:5432

Similarly, other standbys can be created, against pgrepl2 or the pgrepl1 primary.

Marathon will work to make sure that pgrepl1 is running. However, in the case that the Mesos agent hosting pgrepl1 is taken offline, it will be necessary to promote one of the
standbys to primary. This can be done as follows: 

    # ./marathon/promote.sh http://marathon.mesos:8080 pgrepl2 /primary.pgrepl:5432

This will restart the pgrepl2, changing its PGREPL_ROLE environment variable from STANDBY to PRIMARY and causing it to enter primary mode. It will also associate the container with
the VIP primary.pgrepl:5432 formerly associated with pgrepl1, meaning that any downstream apps that had been configured to communicate on that address do not require configuration
changes.

In addition to HA, this process can be used to upgrade the disk allocation for the database. The primary and standby scripts use the environment variable PGREPL_DISK_SIZE to
indicate the disk allocation size, in megabytes. Spinning up a new standby with a larger disk and then promoting it to primary allows the the database disk allocation to be
increased, which is not possible for an existing Mesos task: 

    # PGREPL_DISK_SIZE=250 ./marathon/standby.sh https://marathon.mesos:8080 pgrepl1 pgrepl_bigger /standby.pgrepl:5432
    # # now delete pgrepl1...
    # ./marathon/promote.sh https://marathon.mesos:8080 pgrepl_bigger /primary.pgrepl:5432

---

There are some improvements to be made to this project:

- [ ] Add support for wal archiving
- [ ] Add tool for automatic failover, like repmgr.
- [ ] Mesos framework for deployment, monitoring and automatic failover 
- [ ] DC/OS [Universe](https://github.com/mesosphere/universe) package

The image supports all feautures of the official postgres image, so setting postgres password etc, works, but not done in the above examples.

Replication connection uses a user called pgrepl, and needs a password that is, for now, genereated based on a token. There is a default token, but you can specify your own using environment variables on docker run. I.e. -e PGREPL_TOKEN=thisismytoken






