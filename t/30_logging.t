#!/usr/bin/perl
# $Id: 30_logging.t 566 2007-10-27 01:31:29Z fil $

use strict;
use warnings;

use POE;
use POE::Component::XUL;
use File::Path;
use Data::Dumper;

use Test::More ( tests=> 43 );

use POE::XUL::Logging;
use t::XUL;

our $carpline;

my $logdir = "t/poe-xul/log";
my $logfile = "$logdir/some_log";
my $errorfile = "$logdir/err_log";
if( -d $logdir ) {
    File::Path::rmtree( [ $logdir ] );
}

END {
    File::Path::rmtree( [ $logdir ] );
}


# default logging
my $xul = t::XUL->new( { root => 't/poe-xul', port=>8881, 
                         logging => {
                            error_log   => $errorfile,
                            access_log  => $logfile,
                         }
                     } );
ok( $xul, "Created PoCo::XUL object" );

$xul->log_setup();

ok( -d $logdir, "Created a log dir" );
ok( -f $logfile, "Created the log file" ) 
        or die "I need $logfile";
ok( -f "$logdir/err_log", "Created the error log");

xwarn "Hello world!";
pass( "xwarn didn't die" );

xlog "It is snowing right now.";
pass( "xlog didn't die" );

xdebug "My pants are on fire!";
pass( "xdebug didn't die" );

do_carp();
pass( "xcarp didn't die" );

my $fh = IO::File->new( $logfile );
ok( $fh, "Opened the log file" )
        or die "$logfile: $!";
my $msgs;
{
    local $/;
    $msgs = <$fh>;
}

ok( ($msgs =~ m(WARN Hello world! at t/.+t line \d+\n) ),
                "Log contains xwarn" ) or die "Log:\n$msgs";

ok( ($msgs =~ m(It is snowing right now. at t/.+t line \d+\n) ),
                "Log contains xlog" ) or die "Log:\n$msgs";

ok( ($msgs =~ m(DEBUG My pants are on fire! at t/.+t line \d+\n) ),
                "Log contains xdebug" ) or die "Log:\n$msgs";

ok( ($msgs =~ m(WARN This is a carp message at t/.+t line $carpline)),
                "Log contains xcarp" ) or die "carpline=$carpline\nLog:\n$msgs";


###########################################################
my @EXs;
$xul = t::XUL->new( { root => 't/poe-xul', port=>8881, 
                      logging => {
                            logger      => sub { push @EXs, $_[0] },
                        }
                  } );
ok( $xul, "Created another PoCo::XUL object" );

$xul->log_setup();

xwarn "Hello world!";
pass( "xwarn didn't die" );

xlog "It is snowing right now.";
pass( "xlog didn't die" );

xdebug "My pants are on fire!";
pass( "xdebug didn't die" );

do_carp();
pass( "xcarp didn't die" );

xlog( { type    => 'BONK', 
        message => 'This is a bonk' 
    } );
pass( "xlog w/ hashref didn't die" );

is( 0+@EXs, 6, "6 calls to my prog" )
        or die "EXs=", Dumper \@EXs;

my @check = (
        { directory => $logdir, type=>'SETUP' },
        { caller => [ qw( main t/30_logging.t ) ], 
          message => 'Hello world!', type => 'WARN' },
        { caller => [ qw( main t/30_logging.t ) ], 
          message => 'It is snowing right now.', type => 'LOG' },
        { caller => [ qw( main t/30_logging.t ) ], 
          message => 'My pants are on fire!', type => 'DEBUG' },
        { caller => [ qw( main t/30_logging.t ), $carpline ], 
          message => 'This is a carp message', type => 'WARN' },
        { caller => [ qw( main t/30_logging.t ) ], 
          message => 'This is a bonk', type => 'BONK' },
    );

for( my $w=0; $w < @check ; $w++ ) {
    foreach my $f ( keys %{ $check[$w] } ) {
        my $expect = $check[$w]{$f};
        my $got    = $EXs[$w]{$f};
        unless( $f eq 'caller' ) {
            is( $got, $expect, "$w/$f" );
        }
        else {
            for( my $e=0; $e < @$expect; $e++ ) {
                is( $got->[$e], $expect->[$e], "$w/$f/$e" );
            }
        }
    }
}



###########################################################
sub do_carp
{
    $carpline = __LINE__ + 1;
    __do_carp();
}

sub __do_carp()
{
    xcarp "This is a carp message";
}
