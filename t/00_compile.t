#!/usr/bin/perl -w
# $Id: 00_compile.t 509 2007-09-12 07:20:01Z fil $

use strict;
use warnings;

use Test::More ( tests=>9 );

use_ok( 'POE::XUL::Logging' );
use_ok( 'POE::XUL::State' );
use_ok( 'POE::XUL::Request' );
use_ok( 'POE::XUL::ChangeManager' );
use_ok( 'POE::XUL::Controler' );
use_ok( 'POE::XUL::Node' );
use_ok( 'POE::XUL::Event' );
use_ok( 'POE::XUL::Constants' );
use_ok( 'POE::Component::XUL' );

