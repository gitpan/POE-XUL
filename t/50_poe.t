#!/usr/bin/perl
# $Id: 50_poe.t 604 2007-11-15 23:46:57Z fil $

use strict;
use warnings;

use POE::Component::XUL;
use JSON::XS;
use Data::Dumper;

use constant DEBUG=>0;

use t::PreReq;
use Test::More ( tests=> 138 );
t::PreReq::load( 132, qw( HTTP::Request LWP::UserAgent ) );

use t::Client;
use t::Server;


################################################################

my $Q = 5;

if( $ENV{HARNESS_PERL_SWITCHES} ) {
    $Q *= 3;
}

my $browser = t::Client->new();

my $pid = t::Server->spawn( $browser->{PORT} );
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
is( $data->[1][0], 'boot', "Second response is a boot" );
ok( $data->[1][1], " ... msg" );
is( $data->[2][0], 'new', "Third response is the new" );
is( $data->[2][2], 'window', " ... window" );

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
is( $B1->{tag}, 'button', "Found a button" );

############################################################
$resp = Click( $browser, $B1 );
$data = $browser->decode_resp( $resp, 'click B1' );
$browser->handle_resp( $data, 'click B1' );

is( $D->{nodeValue}, 'You did it!', "The button worked!" )
    or die Dumper $D;

############################################################
my $B2 = $browser->{W}->{zC}[0]{zC}[2];
is( $B2->{tag}, 'button', "Found another button" );

$resp = Click( $browser, $B2 );
$data = $browser->decode_resp( $resp, 'click B2' );
$browser->handle_resp( $data, 'click B2' );

is( $D->{nodeValue}, 'Thank you', "The button is polite" )
    or die Dumper $D;


############################################################
my $other_browser = t::Client->new;
$URI = $other_browser->boot_uri;
$resp = $UA->get( $URI );

$data = $other_browser->decode_resp( $resp, 'boot' );
is( $data->[0][0], 'SID', "First response is the SID" );
is( $data->[1][0], 'boot', "Second response is a boot" );
ok( $data->[1][1], " ... msg" );
is( $data->[2][0], 'new', "Third response is the new" );
is( $data->[2][2], 'window', " ... window" );

$other_browser->handle_resp( $data, 'boot' );

ok( $other_browser->{W}, "Got a window" );
is( $other_browser->{W}->{tag}, 'window', " ... yep" );
ok( $other_browser->{W}->{id}, " ... yep" );

isnt( $browser->{SID}, $other_browser->{SID}, "Distinct SID" );
isnt( $browser->{W}{id}, $other_browser->{W}{id}, "Distinct windows" );

my $oD = $other_browser->{W}->{zC}[0]{zC}[0]{zC}[0];
is( $oD->{tag}, 'textnode', "Found a textnode" );
is( $oD->{nodeValue}, 'do the following', " ... that's telling me what to do" );

my $oB1 = $other_browser->{W}->{zC}[0]{zC}[1];
is( $oB1->{tag}, 'button', "Found a button" );

############################################################
$resp = Click( $other_browser, $oB1 );
$data = $other_browser->decode_resp( $resp, 'click oB1' );
$other_browser->handle_resp( $data, 'click oB1' );

is( $oD->{nodeValue}, 'You did it!', "The button worked!" )
        or die Dumper $oD;
isnt( $D->{nodeValue}, $oD->{nodeValue}, "Didn't affect the other browser" )
        or die Dumper $D;


############################################################
$D->{nodeValue} = 'Something';
$resp = Click( $browser, $B2 );
$data = $browser->decode_resp( $resp, 'click B2 again' );
$browser->handle_resp( $data, 'click B2 again' );

is( $D->{nodeValue}, 'Thank you', "The button is polite" );
isnt( $D->{nodeValue}, $oD->{nodeValue}, "Didn't affect the other browser" );


############################################################
# Test application/x-www-form-urlencoded
my $oB2 = $other_browser->{W}->{zC}[0]{zC}[2];
is( $oB2->{tag}, 'button', "Found another button" );
$resp = ClickPost( $other_browser, $oB2 );

$data = $other_browser->decode_resp( $resp, 'click oB2' );
$other_browser->handle_resp( $data, 'click oB2' );

is( $oD->{nodeValue}, 'Thank you', "The button is polite" )
        or die Dumper $oD;

############################################################
# Test application/x-www-form-urlencoded
$resp = ClickJSON( $other_browser, $oB1 );
$data = $other_browser->decode_resp( $resp, 'click oB1 again' );
$other_browser->handle_resp( $data, 'click oB1 again' );

is( $oD->{nodeValue}, 'You did it!', "The button worked!" )
        or die Dumper $oD;


# use Data::Dumper;
# warn Dumper $browser->{W};


############################################################
sub Click 
{
    my( $browser, $button ) = @_;
    my $URI = $browser->Click_uri( $button );
    return $UA->get( $URI );
}

############################################################
sub ClickPost
{
    my( $browser, $button ) = @_;
    my $URI = $browser->base_uri;
    my $args = $browser->Click_args( $button );
    return $UA->post( $URI, $args );
}

############################################################
sub ClickJSON
{
    my( $browser, $button ) = @_;
    my $URI = $browser->base_uri;
    my $req = HTTP::Request->new( POST => $URI );
    $req->content_type( 'application/json' );
    my $args = $browser->Click_args( $button );
    my $json = to_json( $args );
    $req->content_length( length $json );
    $req->content( $json );
    return $UA->request( $req );
}



