#!/usr/bin/perl -w
# $Id: 00_compile.t 1009 2008-05-23 17:03:36Z fil $

use strict;
use warnings;

use Test::More ( tests=>14 );

use_ok( 'POE::XUL::Logging' );
use_ok( 'POE::XUL::State' );
use_ok( 'POE::XUL::Request' );
use_ok( 'POE::XUL::ChangeManager' );
use_ok( 'POE::XUL::Controler' );
use_ok( 'POE::XUL::Node' );
use_ok( 'POE::XUL::CDATA' );
package Avoid::Redfine::Warning;
main::use_ok( 'POE::XUL::Window' );
package main;
use_ok( 'POE::XUL::TWindow' );
use_ok( 'POE::XUL::Event' );
use_ok( 'POE::XUL::Constants' );
use_ok( 'POE::Component::XUL' );
use_ok( 'POE::XUL::Session' );
use_ok( 'POE::XUL::Application' );

