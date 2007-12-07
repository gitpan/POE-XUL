#!/usr/bin/perl
# $Id: 20_changemanager.t 418 2007-05-18 00:42:25Z fil $

use strict;
use warnings;

use POE::XUL::Node;
use POE::XUL::ChangeManager;
use Data::Dumper;

use Test::More ( tests=> 8 );

##############################
my $CM = POE::XUL::ChangeManager->new();

ok( $CM, "Created the change manager" );

$POE::XUL::Node::CM = $CM;

##############################
# Test setting the ID

my $b = Button( "Button the first", Click => 'Click1', id=>'B1' );
my $W = Window( id=> 'top', $b );

my $buffer = $CM->flush;

is_deeply( $buffer, [
                     [ 'new', 'PX1', 'window', '' ],
                     [ 'set', 'PX1', 'id', 'top' ],
                     [ 'new', 'PX0', 'button', 'top', 0 ],
                     [ 'set', 'PX0', 'label', 'Button the first' ],
                     [ 'set', 'PX0', 'id', 'B1' ]
                    ],  "Default label" )
    or die Dumper $buffer;

#######
$W->appendChild( Label( 'honk' ) );
pxInstructions( 'empty' );

$buffer = $CM->flush;
is_deeply( $buffer, [],  "Instruction: empty" )
    or die Dumper $buffer;

#######
$W->appendChild( Label( 'honk' ) );
pxInstructions( 'flush', 'timeslice' );
$W->appendChild( Label( 'bonk' ) );

$buffer = $CM->flush;
is_deeply( $buffer, [
                [ 'new', 'PX4', 'label', 'top', 2 ],
                [ 'textnode', 'PX4', 0, 'honk' ],
                [ 'timeslice' ],
                [ 'new', 'PX6', 'label', 'top', 3 ],
                [ 'textnode', 'PX6', 0, 'bonk' ],
            ],  "Instructions: flush + timeslice" )
    or die Dumper $buffer;

#######
pxInstructions( 'popup_window' );
$buffer = $CM->flush;
is_deeply( $buffer, [
                [ 'popup_window', 'POEXUL00', {} ],
            ],  "Instruction: popup_window w/ defaults" )
    or die Dumper $buffer;

#######
pxInstructions( [ 'popup_window', 'honk' ] );
$buffer = $CM->flush;
is_deeply( $buffer, [
                [ 'popup_window', 'honk', {} ],
            ],  "Instruction: popup_window w/ default features" )
    or die Dumper $buffer;

#######
pxInstructions( [ 'popup_window', 'bonk', {width=>128} ] );
$buffer = $CM->flush;
is_deeply( $buffer, [
                [ 'popup_window', 'bonk', {width=>128} ],
            ],  "Instruction: popup_window" )
    or die Dumper $buffer;


#######
pxInstructions( [ 'popup_window', 'bonk', {width=>128} ], 
                'empty', 
                [ 'timeslice' ] 
              );
$buffer = $CM->flush;
is_deeply( $buffer, [ [ 'timeslice' ] ],  
            "Multiple instructions" )
    or die Dumper $buffer;
