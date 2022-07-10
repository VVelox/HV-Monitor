# HV::Monitor

## JSON Return

These are all relevant to `.data` in the JSON.

- .VMs :: Hash of the found VMs. VM names are used as the keys. See
  the VM Info Hash Section for more information.
- .totals :: Hash of various compiled totals stats.

### VM Info Hash

- mem_alloc :: Allocated RAM, MB
- mem_use :: Ram in use, MB.
- cpus :: CPU the VM has.
- pcpu :: CPU usage percentage.
- pmem :: Memory usage percentage.
- os_type :: OS the HV regards as the VM as using.
- ip :: Primary IP the HV regards the VM as having. Either blank, an
  IP, or 'DHCP'.
- status_int :: Integer of the current status of the VM.
- console_type :: Console type, VNC or Spice.
- console :: Console address and port.
- snaps_size :: Total size of snapshots.
- snaps :: The number of snapshots for a VM.
- ifs :: Interface array. The name matches `/nic[0-9]+/`.
- syscw
- rchar
- wchar
- rbytes
- wbytes
- cwbytes
- etimes :: Elapsed running time, in decimal integer seconds.
- cow :: Number of copy-on-write faults.
- majflt :: Total page faults.
- minflt :: Total page reclaims.
- nice :: Proc scheduling increment.
- nivcsw :: Total involuntary context switches.
- nswap :: Total swaps in/out.
- nvcsw :: Total voluntary context switches.
- inblk :: Total blocks read.
- oublk :: Total blocks wrote.
- pri :: Scheduling priority.
- rss :: In memory size in Kbytes.
- systime :: Accumulated system CPU time.
- usertime :: Accumulated user CPU time.
- vsz :: Virtual size in Kbytes.

- if
- coll
- drop
- ibytes
- idrop
- ierrs
- ipkgs
- oerrs
- opkts

| State       | Int | Desc                                |
|-------------|-----|-------------------------------------|
| NOSTATE     | 0   | no state                            |
| RUNNING     | 1   | is running                          |
| BLOCKED     | 2   | is blocked on resource              |
| PAUSED      | 3   | is paused by user                   |
| SHUTDOWN    | 4   | is being shut down                  |
| SHUTOFF     | 5   | is shut off                         |
| CRASHED     | 6   | is crashed                          |
| PMSUSPENDED | 7   | suspended by guest power management |
