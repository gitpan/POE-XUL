#!/usr/bin/perl
# $Id: 75_framify.t 509 2007-09-12 07:20:01Z fil $

use strict;
use warnings;

use POE::Component::XUL;
use JSON::XS;
use Data::Dumper;

use constant DEBUG=>0;

use t::PreReq;
use Test::More ( tests=> 532 );
t::PreReq::load( 532, qw( HTTP::Request LWP::UserAgent ) );

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

$browser->handle_resp( $data, 'boot' );
ok( $browser->{W}, "Got a window" );
is( $browser->{W}->{tag}, 'window', " ... yep" );
ok( $browser->{W}->{id}, " ... yep" );


############################################################
my $button = $browser->get_node( 'Framify' );
ok( $button, "Got the Framify button" ) 
        or die "I really need that button";
$URI = $browser->Click_uri( $button );
$resp = $UA->get( $URI );
$data = $browser->decode_resp( $resp, 'click Framify' );
$browser->handle_resp( $data, 'click Framify' );

$button = $browser->get_node( 'Framify' );
ok( !$button, "No more Framify button" );


############################################################
my $gb2 = $browser->get_node( 'IFRAME-GB2' );
ok( $gb2, "Got framified version" )
        or die "I really need that";
is( $gb2->{tag}, "iframe", " ... it's an iframe" );
is( $gb2->{src}{source_id}, 'GB2', 
                " ... refers back to the original element" );

$URI = $browser->base_uri();
my $args = $browser->XULFrom_args( $gb2->{src}{source_id} );
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
ok( ( $xul =~ m/FRAMED-GB2/ ), " ... saw the framed ID" );
ok( ($xul =~ m(<window[^>]+>(.+)</window>)s), " ... window element" )
            or die "XUL=$xul";

my $inside = $1;

ok( ( $inside =~ / id=.GB2./), "Saw the element ID" );
ok( ( $inside =~ /Framify/ ), " ... looks vaguely OK" );