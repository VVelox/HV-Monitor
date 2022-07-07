package HV::Monitor::Backends::Libvirt;

use 5.006;
use strict;
use warnings;

=head1 NAME

HV::Monitor::Backends::Libvirt - Libvirt support for HV::Monitor

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use HV::MOnitor::Backend::Libvirt;
    
    my $backend=HV::MOnitor::Backend::CBSD->new;
    
    my $usable=$backend->usable;
    if ( $usable ){
        $return_hash_ref=$backend->run;
    }

=head1 METHODS

=head2 new

Initiates the backend object.

    my $backend=HV::MOnitor::Backend::Libvirt->new;

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

	my $list_raw = `virsh list  --all --name| grep -v '^$'`;
	if ( $? != 0 ) {
		return {
			data        => {},
			version     => $self->{version},
			error       => 2,
			errorString => '"virsh list  --all --name" exited non-zero',
		};
	}

	my @VMs = split( /\n/, $list_raw );

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

	foreach my $vm (@VMs) {

		my $domstats_raw   = `virsh domstats $vm --nowait | grep -v '^Domain' | grep -v '^$' | sed 's/^[\ \t]*//'`;
		my $domstats       = {};
		my @domstats_split = split( /\n/, $domstats_raw );
		foreach my $line (@domstats_split) {
			chomp($line);
			my ( $stat, $value ) = split( /=/, $line, 2 );
			$domstats->{$stat} = $value;
		}

		# The ones below are linux only, so just zeroing here.
		# syscw syscw rchar wchar rbytes wbytes cwbytes
		my $vm_info = {
			mem_alloc    => 0,
			mem_use      => 0,
			cpus         => 0,
			pcpu         => 0,
			os_type      => 0,
			ip           => '',
			status       => '',
			console_type => '',
			console      => '',
			snaps_size   => 0,
			ifs          => [],
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

		# https://libvirt.org/html/libvirt-libvirt-domain.html#virDomainState
		# VIR_DOMAIN_NOSTATE 	= 	0 (0x0) 	no state
		# VIR_DOMAIN_RUNNING 	= 	1 (0x1) 	the domain is running
		# VIR_DOMAIN_BLOCKED 	= 	2 (0x2) 	the domain is blocked on resource
		# VIR_DOMAIN_PAUSED 	= 	3 (0x3) 	the domain is paused by user
		# VIR_DOMAIN_SHUTDOWN 	= 	4 (0x4) 	the domain is being shut down
		# VIR_DOMAIN_SHUTOFF 	= 	5 (0x5) 	the domain is shut off
		# VIR_DOMAIN_CRASHED 	= 	6 (0x6) 	the domain is crashed
		# VIR_DOMAIN_PMSUSPENDED 	= 	7 (0x7) 	the domain is suspended by guest power management
		if (   $domstats->{'state.state'} eq 1
			|| $domstats->{'state.state'} eq 3
			|| $domstats->{'state.state'} eq 4 )
		{
			my $pid = `ps ax o pid,args | grep qemu | grep ' -name '| grep 'guest='$vm','`;
			chomp($pid);
			$pid =~ s/^[\ \t]*//;
			my $command = $pid;
			$pid     =~ s/[\ \t]+.*$//;
			$command =~ s/^[0-9]+[\ \t]+//;

			my $console_type    = 'unknown';
			my $console_options = $command;
			if ( $command =~ s/[\ \t]-vnc[\t\ ]// ) {
				$console_type = 'vnc';
				$console_options =~ s/.*\-vnc[\t\ ]+//;
			}
			elsif ( $command =~ s/[\ \t]-spice[\t\ ]// ) {
				$console_type = 'spice';
				$console_options =~ s/.*\-spice[\t\ ]+//;
			}
			$console_options =~ s/[\t\ ].*$//;
			$vm_info->{console_type}=$console_type;
			$vm_info->{console}=$console_options;


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
	if ( $^O !~ 'linux' ) {
		die '$^O is "' . $^O . '" and not "linux"';
	}

	# make sure we can locate cbsd
	# Written like this as which on some Linux distros such as CentOS 7 is broken.
	my $cmd_bin = `/bin/sh -c 'which virsh 2> /dev/null'`;
	if ( $? != 0 ) {
		die 'The command "virsh" is not in the path... ' . $ENV{PATH};
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