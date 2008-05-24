package POE::XUL::Controler;
# $Id: Controler.pm 1023 2008-05-24 03:10:20Z fil $
#
# Copyright Philip Gwyn / Awalé 2007-2008.  All rights reserved.
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
            session => $session->ID,
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

    my $tid     = $details->{timeout_id};
    my $session = $details->{session};
    my $CM = $details->{CM};
    if( $tid ) {
        $poe_kernel->alarm_remove( $tid );
    }
    $CM->dispose;
    $poe_kernel->post( $session, 'shutdown', $SID ); # TODO use alias $SID
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

#    use Data::Dumper;
#    xlog "A=", Dumper $A;     
    my $CM = $self->build_change_manager();

    my $event = $self->build_event( 'boot', $CM, $resp );
    $event->__init( $req );
    $event->coderef(
            sub { 
                my( $event ) = @_;
                my $SID = $self->make_session_id;
                $event->SID( $SID );
                $event->CM->SID( $SID );
                my $session = $A->( $event );
                $self->register( $SID, $session, $event->CM );
                $event->defer;
                $poe_kernel->post( $SID, 'boot', $event );
            }
        );

    $self->xul_request( $event );
    return;
}

##############################################################
sub close
{
    my( $self, $SID, $req, $resp ) = @_;

    my $S = $self->{sessions}{ $SID };
    die "Can't find session $SID" unless $SID;

    my $event = $self->build_event( 'close', $S->{CM}, $resp );
    $event->coderef(
            sub { 
                xlog "Close $SID";
                # TODO : use alias $SID
                my $session = $poe_kernel->ID_id_to_session( $S->{session} );
                $poe_kernel->signal( $session, 'UIDESTROY' );
                $self->unregister( $SID );
            }
        );

    $self->xul_request( $event );
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
                        $event->defer;
                        $poe_kernel->post( $SID, 'connect', $event );
                   } );
    $self->xul_request( $event );
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
                        $event->defer;
                        $poe_kernel->post( $SID, 'disconnect', $event );
                   } );
    $self->xul_request( $event );
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

    $self->xul_request( $event );
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
    return 1;
}

##############################################################
## Generate an unguessable session ID.
## Though unguessable isn't all that useful : it can be sniffed off the air
sub make_session_id {
	my $self = shift;
	my $id = md5_base64($$, time, rand(9999));
    $id =~ tr(/+)(-_);
	return $id;
}

1;

