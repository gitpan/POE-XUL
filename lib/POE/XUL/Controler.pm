package POE::XUL::Controler;
# $Id: Controler.pm 654 2007-12-07 14:28:39Z fil $
#
# Copyright Philip Gwyn / Awalé 2007.  All rights reserved.
#

use strict;
use warnings;

use Carp;
use Digest::MD5 qw(md5_base64);
use POE::Kernel;
use POE::XUL::ChangeManager;
use POE::XUL::Event;
use POE::XUL::Logging;

use constant DEBUG => 0;

##############################################################
sub new 
{
    my( $package, $timeout, $apps ) = @_;
	my $self = bless {
		sessions => {},
        timeout  => $timeout,
        apps     => $apps
	}, $package;
	return $self;
}

##############################################################
sub build_event
{
    my( $self, $event_name, $CM, $resp ) = @_;

    return POE::XUL::Event->new( $event_name, $CM, $resp );
}

##############################################################
sub build_change_manager
{
    my( $self ) = @_;

    return POE::XUL::ChangeManager->new();
}




##############################################################
# Does a given session ID exist?
sub exists
{
    my( $self, $SID ) = @_;
    return exists $self->{sessions}{ $SID };
}

##############################################################
# How many sessions currently exist
sub count
{
    my( $self ) = @_;
    return 0 + keys %{ $self->{sessions} };
}


##############################################################
# A new session has been created
sub register
{
    my( $self, $SID, $session, $CM ) = @_;

    DEBUG and xdebug "register SID=$SID";
    # TODO make sure the session has the SID as an alias?
    $self->{sessions}{ $SID } = {
            session => $session,
            CM => $CM
        };
    $self->keepalive( $SID );
}

##############################################################
# A session has been shutdown
sub unregister
{
    my( $self, $SID ) = @_;
    return unless $self->{sessions}{ $SID };
    DEBUG and xdebug "Unregister SID=$SID";
    my $details = delete $self->{sessions}{ $SID };

    my $tid = $details->{timeout_id};
    my $session = $details->{session};
    my $CM = $details->{CM};
    if( $tid ) {
        $poe_kernel->alarm_remove( $tid );
    }
    $CM->dispose;
    $poe_kernel->post( $session, 'shutdown', $SID ); # TODO unit test
}

##############################################################
sub keepalive
{
    my( $self, $SID ) = @_;
    return unless $self->{sessions}{ $SID };
    my $tid = $self->{sessions}{$SID}{timeout_id};
    if( $tid ) {
        
        $poe_kernel->delay_adjust( $tid, $self->{timeout} );
        DEBUG and 
            xdebug "timeout for $SID: tid=$self->{sessions}{$SID}{timeout_id} timeout=$self->{timeout}";
    }    
    else {
        # session_timeout is defined in POE::Component::XUL
        $self->{sessions}{ $SID }{timeout_id} = 
                $poe_kernel->delay_set( 'session_timeout', 
                                        $self->{timeout}, 
                                        $SID );
        DEBUG and 
            xdebug "timeout for $SID: tid=$self->{sessions}{$SID}{timeout_id} timeout=$self->{timeout}";
    }
}


##############################################################
# Find the constructor for a package
sub package_ctor
{
    my( $self, $package ) = @_;
    
    confess "No package" unless $package;
    return $package->can( 'spawn' );
}

##############################################################
# Spawn a component from a package
sub package_build
{
    my( $self, $package ) = @_;
    my $ctor = $self->package_ctor( $package );
    unless( $ctor ) {
        return sub {
                my( $event ) = @_;
                $event->response->content( "Can't build an application from $package" );
                $event->response->code( 500 );
            };
    }
    return sub { $ctor->( $package, @_ ) };
}


##############################################################
sub boot
{
    my( $self, $req, $resp ) = @_;
    my $app = $req->param( 'app' );
    my $A = $self->{apps}{$app};

    unless( $A ) {
        xlog "Unknown application: $app";
        return "Application inconue : $app";
    }

    unless( ref $A ) {
        $A = $self->package_build( $A );
    }
     
    my $CM = $self->build_change_manager();

    my $event = $self->build_event( 'boot', $CM, $resp );
    $event->coderef(
            sub { 
                my( $event ) = @_;
                my $SID = $self->make_session_id;
                $event->SID( $SID );
                $event->CM->SID( $SID );
                my $session = $A->( $event );
                $self->register( $SID, $session, $event->CM );
                $event->done( 0 );
                $poe_kernel->post( $SID, 'boot', $event );
            }
        );

    $self->do_request( $event );
    return;
}

##############################################################
sub connect
{
    my( $self, $SID, $req, $resp ) = @_;

    my $S = $self->{sessions}{ $SID };
    die "Can't find session $SID" unless $SID;

    my $event = $self->build_event( 'connect', $S->{CM}, $resp );
    $event->__init( $req );

    $event->coderef( sub {
                        $event->done( 0 );
                        $poe_kernel->post( $SID, 'connect', $event );
                   } );
    $self->do_request( $event );
    return;
}

##############################################################
sub disconnect
{
    my( $self, $SID, $req, $resp ) = @_;

    my $S = $self->{sessions}{ $SID };
    die "Can't find session $SID" unless $SID;

    my $event = $self->build_event( 'disconnect', $S->{CM}, $resp );
    $event->__init( $req );

    $event->coderef( sub {
                        $event->done( 0 );
                        $poe_kernel->post( $SID, 'disconnect', $event );
                   } );
    $self->do_request( $event );
    return;
}

##############################################################
sub request 
{
	my ( $self, $SID, $event_type, $req, $resp ) = @_;

    my $S = $self->{sessions}{ $SID };
    die "Can't find session $SID" unless $SID;

    my $event = $self->build_event( $event_type, $S->{CM}, $resp );
    $event->__init( $req );

    $self->do_request( $event );
}

##############################################################
sub do_request
{
    my( $self, $event ) = @_;

    my $cmd = $event->event;
    if( $cmd eq 'XUL-from' ) {
        $self->xul_from( $event );
    }
    else {
        $self->xul_request( $event );
    }
    return 1;
}


##############################################################
# Standard XUL request (Click / Change / etc )
sub xul_request 
{
	my( $self, $event ) = @_;

    $event->done( 1 );
    $event->run();
    DEBUG and xdebug "Request done";
    if( $event->is_flushed ) {
        # User code might have already flushed everything
        DEBUG and xdebug "Request already flushed";
    }
    elsif( $event->done ) {
        DEBUG and xdebug "Response now";
        $event->flush;
    }
    else {
        # User code wants us to wait
        DEBUG and xdebug "Defered response";
    }
}

##############################################################
# Browser wants part of the XUL tree as XML
# This was a failed attempt at sending XUL fragments.  
sub xul_from
{
    my( $self, $event ) = @_;

    # get the XUL of the node
    my $inside = $event->source->as_xml;
    my $id = $event->source->id;

    DEBUG and xdebug "Get $id as XUL";

    # get the surrounding bits
    my $file = $event->get( 'Fragment-XUL' );

    my $io = IO::File->new( $file );
    die "Can't open $file: $!" unless $io;
    
    my $xul = join '', <$io>;

    # insert the XUL fragment
    $xul =~ s/\[\[FRAGMENT\]\]/$inside/;
    $xul =~ s/\[\[ID\]\]/$id/g;

    $event->CM->xul_response( $event->resp, $xul );
}



##############################################################
## Generate an unguessable session ID.
## Though unguessable isn't all that useful : it can be sniffed off the air
sub make_session_id {
	my $self = shift;
	my $id = md5_base64($$, time, rand(9999));
    $id =~ tr(/+)(_-);
	return $id;
}

1;

