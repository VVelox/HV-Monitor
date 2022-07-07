package HV::Monitor::Backends::CBSD;

use 5.006;
use strict;
use warnings;

=head1 NAME

HV::Monitor::Backends::CBSD - CBSD support for HV::Monitor

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use HV::MOnitor::Backend::CBSD;
    
    my $backend=HV::MOnitor::Backend::CBSD->new;
    
    my $usable=$backend->usable;
    if ( $usable ){
        $return_hash_ref=$backend->run;
    }

=head1 METHODS

=head2 new

Initiates the backend object.

    my $backend=HV::MOnitor::Backend::CBSD->new;

=cut

sub new {
	my $self = { version => 1, };
	bless $self;

	return $self;
}

=head2 run

    $return_hash_ref=$backend->run;

=cut

sub run {
	my $self = $_[0];

	my $bls_raw
		= `/bin/sh -c "cbsd bls header=0 node= display=jname,jid,vm_ram,vm_curmem,vm_cpus,pcpu,vm_os_type,ip4_addr,status,vnc alljails=0 2> /dev/null" | sed -e 's/\x1b\[[0-9;]*m//g'`;
	if ( $? != 0 ) {
		return {
			data        => {},
			version     => $self->{version},
			error       => 2,
			errorString =>
				'"cbsd bls header=0 node= display=jname,jid,vm_ram,vm_curmem,vm_cpus,pcpu,vm_os_type,ip4_addr,status,vnc alljails=0" exited non-zero',
		};
	}

	#remove color codes
	$bls_raw =~ s/\^.{1,7}?m//g;

	my @VMs;

	my $ifs_raw = `ifconfig | grep '^[A-Za-z]' | cut -d: -f 1`;
	my @ifs     = split( /\n/, $ifs_raw );

	my $return_hash = {
		VMs    => {},
		totals => {
			'usertime'    => 0,
			'pmem'        => 0,
			'mem_use'     => 0,
			'oublk'       => 0,
			'minflt'      => 0,
			'pcpu'        => 0,
			'mem_alloc'   => 0,
			'nvcsw'       => 0,
			'snaps'       => 0,
			'rss'         => 0,
			'snaps_size'  => 0,
			'cpus'        => 0,
			'cow'         => 0,
			'nivcsw'      => 0,
			'systime'     => 0,
			'vsz'         => 0,
			'etimes'      => 0,
			'majflt'      => 0,
			'inblk'       => 0,
			'nswap'       => 0,
			'on'          => 0,
			'off'         => 0,
			'off_hard'    => 0,
			'off_soft'    => 0,
			'unknown'     => 0,
			'paused'      => 0,
			'crashed'     => 0,
			'blocked'     => 0,
			'nostate'     => 0,
			'pmsuspended' => 0,
		}
	};

	# values that should be totaled
	my @total = (
		'usertime', 'pmem',   'mem_use',    'oublk', 'minflt', 'pcpu',   'mem_alloc', 'nvcsw',
		'snaps',    'rss',    'snaps_size', 'cpus',  'cow',    'nivcsw', 'systime',   'vsz',
		'etimes',   'majflt', 'inblk',      'nswap'
	);

	my @bls_split = split( /\n/, $bls_raw );
	foreach my $line (@bls_split) {
		chomp($line);
		my ( $vm, $pid, $mem_alloc, $mem_use, $cpus, $pcpu, $vm_os_type, $ip, $status, $vnc )
			= split( /[\ \t]+/, $line );

		# The ones below are linux only, so just zeroing here.
		# syscw syscw rchar wchar rbytes wbytes cwbytes
		my $vm_info = {
			mem_alloc    => $mem_alloc,
			mem_use      => $mem_use,
			cpus         => $cpus,
			pcpu         => $pcpu,
			os_type      => $vm_os_type,
			ip           => $ip,
			status       => $status,
			console_type => 'vnc',
			console      => $vnc,
			snaps_size   => 0,
			ifs          => {},
			syscw        => 0,
			syscw        => 0,
			rchar        => 0,
			wchar        => 0,
			rbytes       => 0,
			wbytes       => 0,
			cwbytes      => 0,
			etimes       => 0,
			pmem         => 0,
			cow          => 0,
			majflt       => 0,
			minflt       => 0,
			nice         => 0,
			nivcsw       => 0,
			nswap        => 0,
			nvcsw        => 0,
			inblk        => 0,
			oublk        => 0,
			pri          => 0,
			rss          => 0,
			systime      => 0,
			usertime     => 0,
			vsz          => 0,
		};

		if ( $status =~ /^On/ ) {
			$vm_info->{status_int} = 0;
			$return_hash->{totals}{on}++;
			my $additional
				= `ps S -o pid,etimes,%mem,cow,majflt,minflt,nice,nivcsw,nswap,nvcsw,inblk,oublk,pri,rss,systime,usertime,vsz | grep '^ *'$pid'[\ \t]'`;

			chomp($additional);
			(
				$pid,               $vm_info->{etimes}, $vm_info->{pmem},    $vm_info->{cow},
				$vm_info->{majflt}, $vm_info->{minflt}, $vm_info->{nice},    $vm_info->{nivcsw},
				$vm_info->{nswap},  $vm_info->{nvcsw},  $vm_info->{inblk},   $vm_info->{oublk},
				$vm_info->{pri},    $vm_info->{rss},    $vm_info->{systime}, $vm_info->{usertime},
				$vm_info->{vsz}
			) = split( /[\ \t]+/, $additional );

			# zero anything undefined
			my @keys = keys( %{$vm_info} );
			foreach my $info_key (@keys) {
				if ( !defined( $vm_info->{$info_key} ) ) {
					$vm_info->{$info_key} = 0;
				}
			}

			# process the snapshots
			my $snaplist_raw = `cbsd jsnapshot mode=list jname=$vm | sed -e 's/\x1b\[[0-9;]*m//g'`;
			my @snaplist     = split( /\n/, $snaplist_raw );

			# line 0 is always the header
			my $snaplist_int = 1;
			while ( defined( $snaplist[$snaplist_int] ) ) {
				chomp( $snaplist[$snaplist_int] );

				my ( $jname, $snapname, $snap_creation, $refer ) = split( /[\ \t]+/, $snaplist[$snaplist_int] );

				if ( $refer =~ /[Kk]$/ ) {
					$refer =~ s/[Kk]$//;
					$refer = $refer * 1000;
				}
				elsif ( $refer =~ /[Mm]$/ ) {
					$refer =~ s/[Mm]$//;
					$refer = $refer * 1000000;
				}
				elsif ( $refer =~ /[Gg]$/ ) {
					$refer =~ s/[Gg]$//;
					$refer = $refer * 1000000000;
				}
				elsif ( $refer =~ /[Tt]$/ ) {
					$refer =~ s/[Tt]$//;
					$refer = $refer * 1000000000000;
				}

				$vm_info->{snaps_size} = $vm_info->{snaps_size} + $refer;

				$snaplist_int++;
			}

			$vm_info->{snaps} = $#snaplist;

			my ( $minutes, $seconds ) = split( /\:/, $vm_info->{systime} );
			$vm_info->{systime} = ( $minutes * 60 ) + $seconds;

			( $minutes, $seconds ) = split( /\:/, $vm_info->{usertime} );
			$vm_info->{usertime} = ( $minutes * 60 ) + $seconds;

			#
			# NIC info
			#

			my @bnics_raw = split( /\n/,
				`cbsd bhyve-nic-list display=nic_parent,nic_hwaddr jname=$vm | sed -e 's/\x1b\[[0-9;]*m//g'` );
			my $bnics_int = 1;
			if ( defined( $bnics_raw[$bnics_int] ) ) {
				chomp( $bnics_raw[$bnics_int] );
				my @line_split = split( /[\ \t]+/, $bnics_raw[$bnics_int] );

				my $nic_info = {
					mac    => $line_split[1],
					parent => $line_split[0],
					if     => '',
					ipkgs  => 0,
					ierrs  => 0,
					ibytes => 0,
					idrop  => 0,
					opkts  => 0,
					oerrs  => 0,
					obytes => 0,
					coll   => 0,
					odrop  => 0,
					drop   => 0,
				};

				$vm_info->{ifs}{ 'nic' . $bnics_int } = $nic_info;

				$bnics_int++;
			}

			# get a list of NICs the VM uses
			my $VM_ifs = {};

			# go through each
			foreach my $interface (@ifs) {
				my $if_raw = `ifconfig $interface | grep -E 'description: ' | cut -d: -f 2- | head -n 1`;
				chomp($if_raw);
				$if_raw =~ s/^[\'\"\ ]+//;
				$if_raw =~ s/[\'\"]$//;
				if ( $if_raw =~ /^$vm-nic[0-9]+/ ) {
					my $nic = $if_raw;
					$nic =~ s/^$vm\-//;

					$vm_info->{ifs}{$nic}{if} = $interface;

					my @netstats     = split( /\n/, `netstat -ibdWn -I $interface` );
					my $netstats_int = 1;
					my @add_stats    = ( 'ipkgs', 'ierrs', 'idrop', 'ibytes', 'opkts', 'oerrs', 'coll', 'drop' );
					while ( defined( $netstats[$netstats_int] ) ) {
						my $line = $netstats[$netstats_int];
						chomp($line);

						my $if_stats = {};

						(
							$if_stats->{int},   $if_stats->{mtu},   $if_stats->{network}, $if_stats->{address},
							$if_stats->{ipkgs}, $if_stats->{ierrs}, $if_stats->{idrop},   $if_stats->{ibytes},
							$if_stats->{opkts}, $if_stats->{oerrs}, $if_stats->{obytes},  $if_stats->{coll},
							$if_stats->{drop}
						) = split( /[\ \t]+/, $line );

						foreach my $current_stat (@add_stats) {
							if ( $if_stats->{$current_stat} =~ /^[0-9]+$/ ) {
								$vm_info->{ifs}{$nic}{$current_stat} += $if_stats->{$current_stat};
							}
						}

						$netstats_int++;
					}
				}
			}

			foreach my $to_total (@total) {
				$return_hash->{totals}{$to_total} = $return_hash->{totals}{$to_total} + $vm_info->{$to_total};
			}
		}
		elsif ( $status =~ /^[Oo][Ff][Ff]/ ) {
			$vm_info->{status_int} = 1;
			$return_hash->{totals}{off}++;
		}
		else {
			# CBSD also has some mode called maintenance and slave,
			# but it is very unclear what those are
			$vm_info->{status_int} = 2;
			$return_hash->{totals}{unknown}++;
		}

		$return_hash->{VMs}{$vm} = $vm_info;
		push( @VMs, $vm );
	}

	return {
		version     => $self->{version},
		error       => 0,
		errorString => '',
		data        => $return_hash,
	};
}

=head2 usable

Dies if not usable.

    eval{ $backend->usable; };
    if ( $@ ){
        print 'Not usable because... '.$@."\n";
    }

=cut

sub usable {
	my $self = $_[0];

	# Make sure we are on a OS on which ZFS is usable on.
	if ( $^O !~ 'freebsd' ) {
		die '$^O is "' . $^O . '" and not "freebsd"';
	}

	# make sure we can locate cbsd
	# Written like this as which on some Linux distros such as CentOS 7 is broken.
	my $cmd_bin = `/bin/sh -c 'which cbsd 2> /dev/null'`;
	if ( $? != 0 ) {
		die 'The command "cbsd" is not in the path... ' . $ENV{PATH};
	}

	return 1;
}

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-hv-monitor at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=HV-Monitor>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc HV::Monitor


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=HV-Monitor>

=item * CPAN Ratings

L<https://cpanratings.perl.org/d/HV-Monitor>

=item * Search CPAN

L<https://metacpan.org/release/HV-Monitor>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2022 by Zane C. Bowers-Hadley.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut

1;
