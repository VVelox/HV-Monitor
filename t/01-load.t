#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'HV::Monitor::Backends::CBSD' ) || print "Bail out!\n";
}

diag( "Testing HV::Monitor::Backends::CBSD $HV::Monitor::Backends::CBSD::VERSION, Perl $], $^X" );
