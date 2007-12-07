#!/usr/bin/perl
# $Id: 56_timeout.t 604 2007-11-15 23:46:57Z fil $

use strict;
use warnings;

use POE::Component::XUL;
use JSON::XS;
use Data::Dumper;

use constant DEBUG=>0;

use t::PreReq;
use Test::More ( tests=> 48 );
t::PreReq::load( 48, qw( HTTP::Request LWP::UserAgent ) );

use t::Client;
use t::Server;

our $HAVE_ALGORITHM_DIFF;
BEGIN {
    eval "use Algorithm::Diff";
    $HAVE_ALGORITHM_DIFF = 1 unless $@;
}


################################################################

my $Q = 5;

if( $ENV{HARNESS_PERL_SWITCHES} ) {
    $Q *= 3;
}

my $browser = t::Client->new();

my $pid = t::Server->spawn( $browser->{PORT}, 'poe-xul', 't/test-timeout.pl' );
END { kill 2, $pid if $pid; }

diag( "sleep $Q" );
sleep $Q;

my $UA = LWP::UserAgent->new;

$UA->timeout( 2*60 );

############################################################
my $URI = $browser->root_uri;
$URI->path( '/__poe_size' );
my $resp = $UA->get( $URI );
ok( $resp->is_success, "Got the kernel size" );
is( $resp->content_type, 'text/plain', " ... as text/plain" );

my $SIZE1 = 0+$resp->content;
ok( $SIZE1, " ... and it is non-null" );
my $DUMP1;
if( $SIZE1 > 0 ) {
    $URI->path( '/__poe_kernel' );
    $resp = $UA->get( $URI );
    $DUMP1 = $resp->content;
}



############################################################
$URI = $browser->boot_uri;
$resp = $UA->get( $URI );

my $data = $browser->decode_resp( $resp, 'boot' );
is( $data->[0][0], 'SID', "First response is the SID" );
# no boot message, this is t/test-timeout.pl
is( $data->[1][0], 'new', "Second response is the new" );
is( $data->[1][2], 'window', " ... window" );

$browser->handle_resp( $data, 'boot' );

ok( $browser->{W}, "Got a window" );
is( $browser->{W}->{tag}, 'window', " ... yep" );
ok( $browser->{W}->{id}, " ... yep" );

my $D = $browser->{W}->{zC}[0]{zC}[0]{zC}[0];
is( $D->{tag}, 'textnode', "Found a textnode" )
        or die Dumper $D;
is( $D->{nodeValue}, 'do the following', " ... that's telling me what to do" )
            or die Dumper $D;

my $B1 = $browser->{W}->{zC}[0]{zC}[1];
is( $B1->{tag}, 'button', "Found a button" )
    or die "I really need that button";

############################################################
my $SIZE2 = 0;
SKIP: {
    skip "Don't have Devel::Size", 4 unless $SIZE1 > 0;

    $URI = $browser->root_uri;
    $URI->path( '/__poe_size' );
    $resp = $UA->get( $URI );
    ok( $resp->is_success, "Got the kernel size" );
    is( $resp->content_type, 'text/plain', " ... as text/plain" );

    $SIZE2 = 0+$resp->content;
    ok( $SIZE2, " ... and it is non-null" );
    ok( ($SIZE2 > $SIZE1), "Kernel grew" );
}


############################################################
diag( "sleep 10" );
sleep 7;

$resp = Click( $browser, $B1 );

ok( !$resp->is_success, "Failed the request" );
ok( ($resp->content =~ /$browser->{SID}/), " ... the session" );
is( $resp->code, 410, " ... it's gone" );
ok( ($resp->content =~ /Session inexistante/), " ... is timed-out" );


############################################################
my $SIZE3 = 0;
SKIP: {
    skip "Don't have Devel::Size", 5 unless $SIZE2 > 0;

    $URI = $browser->root_uri;
    $URI->path( '/__poe_size' );
    $resp = $UA->get( $URI );
    ok( $resp->is_success, "Got the kernel size" );
    is( $resp->content_type, 'text/plain', " ... as text/plain" );

    $SIZE3 = 0+$resp->content;
    ok( $SIZE3, " ... and it is non-null" );
    ok( ($SIZE3 < $SIZE2), "Kernel shrunk again" );

    my $delta = abs( $SIZE3 - $SIZE1 );
    ok( ($delta < 60), " ... close enough to original size ($delta)" );

    if( DEBUG and $delta > 0 and $HAVE_ALGORITHM_DIFF ) {
        $URI->path( '/__poe_kernel' );
        $resp = $UA->get( $URI );
        my $DUMP2 = $resp->content;

        my $diff = Algorithm::Diff->new( [ split "\n", $DUMP1 ], 
                                         [ split "\n", $DUMP2 ] );
        $diff->Base( 1 );   # Return line numbers, not indices
        while(  $diff->Next()  ) {
            next   if  $diff->Same();
            my $sep = '';
            if(  ! $diff->Items(2)  ) {
                printf "%d,%dd%d\n",
                   $diff->Get(qw( Min1 Max1 Max2 ));
            } elsif(  ! $diff->Items(1)  ) {
                printf "%da%d,%d\n",
                   $diff->Get(qw( Max1 Min2 Max2 ));
            } else {
                $sep = "---\n";
                printf "%d,%dc%d,%d\n",
                   $diff->Get(qw( Min1 Max1 Min2 Max2 ));
            }
            print "< $_\n"   for  $diff->Items(1);
            print $sep;
            print "> $_\n"   for  $diff->Items(2);
        }

        # diag( $diff );

        if( DEBUG ) {
            diag( "SIZE1=$SIZE1" );
            diag( "SIZE2=$SIZE2" );
            diag( "SIZE3=$SIZE3" );
        }
    }
}




############################################################
sub Click 
{
    my( $browser, $button ) = @_;
    my $URI = $browser->Click_uri( $button );
    return $UA->get( $URI );
}

