# docker-pgrepl

This Dockerfile uses the standard postgres 9.4 docker image and adds a script that sets up streaming repliaction between two or more docker containers runningPostgres.

This is a PoC, and is not intended to be used for production scenarios. 

To clone this git repo run:

    # git clone https://github.com/mgudmund/docker-pgrepl.git

To build the docker image do:

    # docker build -t postgres_repl .

To create the first docker container with the master node run:

    # docker run -d -P --name pgrepl1  postgres_repl 

Check the logs to see if postgres started correctly:

    # docker logs pgrepl1
    ...
    LOG:  database system was shut down at 2015-06-30 08:14:39 UTC
    LOG:  MultiXact member wraparound protections are now enabled
    LOG:  database system is ready to accept connections
    LOG:  autovacuum launcher started
    

To add a standby to the master, pgrepl1, run:

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
    
To add a second standby to the master, pgrepl1, run:

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
To promote a standby to become a master, you can use docker exec. Example:

If pgrepl1 crashes, run the following command to promote pgrepl2 to become the master
  
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
        

This would promte pgrepl2 to be the master. The downstream standby from pgrepl2, pgrepl4 will switch timelines and continue to be the downstream standby. 
pgrepl3 would in this case not have any master to connect to. You could reconfigure it to follow pgrepl2, or just remove it and create a new standby, downstream from pgrepl2.

When Docker Swarm gets some more love, and support networking between the swarm nodes when using --link, you could easily make sure your master and standby's each end up on different nodes, by using affinity:container!=upstream_node






