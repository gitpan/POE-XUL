#!/usr/bin/perl
# $Id: 70_xul_from.t 509 2007-09-12 07:20:01Z fil $

use strict;
use warnings;

use POE::Component::XUL;
use JSON::XS;
use Data::Dumper;

use constant DEBUG=>0;

use t::PreReq;
use Test::More ( tests=> 12 );
t::PreReq::load( 13, qw( HTTP::Request LWP::UserAgent ) );

use t::Client;
use t::Server;


################################################################

my $Q = 5;

if( $ENV{HARNESS_PERL_SWITCHES} ) {
    $Q *= 3;
}

my $browser = t::Client->new( APP=>'Complete' );

my $pid = t::Server->spawn( $browser->{PORT}, 'poe-xul' );
END { kill 2, $pid if $pid; }


diag( "sleep $Q" );
sleep $Q;

my $UA = LWP::UserAgent->new;

$UA->timeout( 2*60 );

############################################################
my $URI = $browser->boot_uri;
my $resp = $UA->get( $URI );

my $data = $browser->decode_resp( $resp, 'boot' );
is( $data->[0][0], 'SID', "First response is the SID" );
is( $data->[1][0], 'new', "Second response is the new" );
is( $data->[1][2], 'window', " ... window" );

$browser->{SID} = $data->[0][1];

# $browser->handle_resp( $data, 'boot' );
# ok( $browser->{W}, "Got a window" );
# is( $browser->{W}->{tag}, 'window', " ... yep" );
# ok( $browser->{W}->{id}, " ... yep" );


############################################################
$URI = $browser->base_uri;
my $args = $browser->XULFrom_args( 'XUL-SID' );
$resp = $UA->post( $URI, $args );

ok( $resp->is_success, "Got one bit of the tree" ) 
            or die $resp->as_string;
is( $resp->content_type, 'application/vnd.mozilla.xul+xml', 
                    " ... and it's XUL" );
my $xul = $resp->content;
is( length( $xul ), $resp->content_length, " ... proper length" );
ok( (substr( $xul, 0, 21 ) eq '<?xml version="1.0"?>'), 
            " ... XML preamble" )
            or die "XUL=$xul";
ok( ($xul =~ m(<window[^>]+>(.+)</window>)s), " ... window element" )
            or die "XUL=$xul";
my $inside = $1;

ok( index( $inside, "<description id='XUL-SID'>$browser->{SID}</description>") 
        > -1, 
            " ... and the right contents" ) or die "INSIDE=$inside";


