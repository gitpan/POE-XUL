package POE::XUL::Event;
# $Id: Event.pm 654 2007-12-07 14:28:39Z fil $
# Copyright Philip Gwyn 2007.  All rights reserved.
# Based on code Copyright 2003-2004 Ran Eilam. All rights reserved.

use strict;
use warnings;

use Carp;
use POE;
use POE::XUL::Logging; 

use constant DEBUG => 0;

##############################################################
sub new
{
	my( $package, $event_type, $CM, $resp ) = @_;

    croak "Why didn't you give me a ChangeManager" unless $CM;
    croak "Why didn't you give me a HTTP::Response" unless $resp;

    $CM->request_start();

    my $self = bless {
            event_type => $event_type,
            CM         => $CM,
            resp       => $resp
        }, $package;

    return $self;
}

##############################################################
sub __init
{
    my( $self, $req ) = @_;

    if( $self->{event_type} ne 'connect' and 
                $self->{event_type} ne 'disconnect' ) {
        my $source_id = $req->param( 'source_id' );
        my $rc = $self->__source_id( $source_id );
        die $rc if $rc;
    }
    foreach my $f ( $req->params ) {
        next if $f eq 'source_id';
        $self->set( $f => $req->param( $f ) );
    }

    foreach my $f ( qw( Fragment-XUL ) ) {
        $self->set( $f => $req->header( $f ) );
    }
}


##############################################################
sub __source_id
{
    my( $self, $id ) = @_;

    my $node = $self->{CM}->getElementById( $id );
    return "Can't find source node $id" unless $node;
    $self->{source} = $node;
    $self->{source_id} = $id;
    return;
}

##############################################################
sub coderef
{
    my( $self, $coderef ) = @_;
    $self->{coderef} = $coderef;
}

##############################################################
# Accessors
sub set { $_[0]->{ $_[1] } = $_[2] }
sub get { $_[0]->{ $_[1] } }
sub name { 
    return $_[0]->{event_type} unless 2==@_;
    $_[0]->{event_type} = $_[1];
}
*event = \&name;
sub type { $_[0]->{event_type} }
sub session { 
    carp "Please use SID() instead of session()";
    shift->SID( @_ ) 
}

# general accessor/mutator
sub AUTOLOAD {
	my $self = shift;
	my $key  = our $AUTOLOAD;
	return if $key =~ /DESTROY$/;
	$key =~ s/^.*:://;
	return $self->{$key} if @_ == 0;
	$self->{$key} = shift;
}

*target = \&source;

##############################################################
sub run
{
    my( $self ) = @_;


    # Keep the Node in sync with the browser elements
    my $method = "handle_" . $self->event;
    my $CMm = $self->{CM}->can( $method );

    if( $CMm ) {
        DEBUG and xdebug "$method = $CMm";
        $self->wrap( sub { $CMm->( $self->{CM}, $self ) } ) ;
        return if $self->{responded};
    }

    # Call code that our builder thinks we should execute
    if( $self->{coderef} ) {
        DEBUG and xdebug "coderef";
        $self->wrap( $self->{coderef} );
    }
    # Call code that the application thinks we should execute
    else {
        DEBUG and xdebug "do_event";
        $self->do_event();
    }
}

sub do_event
{
    my( $self ) = @_;

    my $bt = delete $self->{bubble_to};
    foreach my $N ( $self->{source}, $bt ) {
        next unless $N;

        my $listener = $N->event( $self->{event_type} );
        DEBUG and 
            xdebug "========== $N listener=$listener";
        next unless $listener;

        $self->{source} = $N;

        $self->wrap( sub {
                if( ref $listener ) {
                    $listener->( $self );
                }
                else {
                    DEBUG and xdebug "Posting to $self->{SID}/$listener";
                    $poe_kernel->call( $self->{SID}, $listener, $self );
                }
            } );
        last;
    }
}


##############################################################
sub finish
{
    my( $self ) = @_;

    $self->done( 1 );
    DEBUG and xcarp "Event finished";

    $self->flush();
}

##############################################################
sub wrap
{
    my( $self, $coderef ) = @_;

    eval {
        local $SIG{__DIE__} = 'DEFAULT';
        DEBUG and 
            xcarp "Wrapping user code";
        local $POE::XUL::Node::CM;
        $POE::XUL::Node::CM = $self->{CM};
        $coderef->( $self );
    };

    if( $@ ) {
        my $err = "APPLICATION ERROR: $@";
        # DEBUG and 
            xdebug $err;
        $self->wrapped_error( $err );
        return;
    }
}

##############################################################
sub flushed
{
    my( $self ) = @_;
    return $self->{is_flushed};
}

##############################################################
sub flush
{
    my( $self ) = @_;

    if( $self->{is_flushed} ) {
        Carp::confess "This event was already flushed!";
        return;
    }
    $self->{CM}->response( $self->{resp} );
    $self->{is_flushed} = 1;
}

##############################################################
sub wrapped_error
{
    my( $self, $err ) = @_;
    $self->{CM}->error_response( $self->{resp}, $err );
}

1;

__DATA__

=head1 NAME

POE::XUL::Event - A DOM event

=head1 SYNOPSIS

    sub xul_Handler {
        my( $self, $event ) = @_[ OBJECT, EVENT ];
        warn "Event ", $event->name, " on ", $event->target->id;
        $event->done( 0 );
        $poe_kernel->yield( other_event => $event );
    }

    sub other_event {
        my( $self, $event ) = @_[ OBJECT, EVENT ];
        $event->wrap( sub {
                # ... do work
                $event->finish;
            } );
    }

=head1 DESCRIPTION

User interaction with the browser's DOM may provoke a DOM event.  These
events are handled by the Javascript client library, which will send them
to the L<POE::XUL> server.  C<POE::XUL> encapsulates the event as a
POE::XUL::Event object.  This object associates an application's
L<POE::XUL::Nodes> with the application's L<POE::XUL::ChangeManager>.

First, the ChangeManager handles all side-effects of an event, such as
setting the target node's C<value> attribute.

Next, if there is a listener defined for the event, further execution is
wrappedso that any changes to a Node will be seen by the ChangeManager and
the listener is called.


Note that L<POE::XUL::Events> to not I<bubble> up the DOM tree like DOM
events do.

=head1 METHODS

=head2 name / type / event

    my $name = $event->name;

Accessor that returns the name of the event.  Normaly one of L</Click>,
L</Change>, L</Select> or L</Pick>.

=head2 SID

    my $SID = $event->SID;
    my $instance = $heap->{ $SID };

Returns the session ID of the current application instance.  This is roughly
equivalent to a PID.

=head2 target / source

    my $node = $event->target;

Returns the L<POE::XUL::Node> that was the target of the event.  For
C<Click> this is the a C<Button>, for C<Change>, a C<TextBox>, for
C<Select>, the node you attached the event (either C<RadioGroup>, C<Radio>
C<MenuList> or C<MenuItem>).

=head2 done

    $event->done( $state );
    $state = $event->done;

Mark the current event as completed.  Or not.  Initially, an event is marked
as completed.  If you wish to defer the event to another POE state, you may
set done to 0, and then call L</finish> later.

=head2 finish

    $event->finish;

Mark the current event as completed, and flush any changes from the
ChangeManager to the browser.  You only have to call this if you set
L</done> to 0 perviously.

=head2 wrap

    $event->wrap( $coderef );

Wrap a coderef in this event.  This has 2 effects:

First, activates the application's ChangeManager, so that any new or 
modified L<POE::XUL::Node> are seen by it.

Second, if the coderef dies, the error message is displayed in the browser.

=head2 flushed

    die "Too late!" if $event->flushed;

Returns true if the current event has already been flushed to the browser.
Because L<POE::XUL> uses a synchronous-event-based model, an event may only
be flushed once.  This, however, should change later at some point.

=head1 DOM EVENTS

=head2 Click

    sub Click {
        my( $self, $event ) = @_[ OBJECT, ARG0 ];
        my $button = $event->source;
    }

The most important event; most action in the application will be in reaction to
the user clicking a button or other control.

=head2 Change

    sub Change {
        my( $self, $event ) = @_[ OBJECT, ARG0 ];
        my $node = $event->source;
        my $value = $event->value;
    }

A less important event, C<Change> is called when the value of a TextBox has
changed.  The application does not have to update the source node's value;
this is a side-effect handled by the ChangeManager.

=head2 Select

    sub Select {
        my( $self, $event ) = @_[ OBJECT, ARG0 ];
        my $list =  $event->source;
        my $selected = $list->getItemAtIndex( $list->selectIndex );
        my $value = $selected->value;
    }

This event happens when a user selects an item in a menulist, radiogroup,
list or other.  The event may also be attached to the menulist or radiogroup
itself.

The target node will be the menulist or radiogroup.  These node's
C<selected> is set as a side-effect by the ChangeManager.

=head2 Pick

    sub Pick {
        my( $self, $event ) = @_[ OBJECT, ARG0 ];
    }

Called when the users selects a colour in a Colorpicker, Datepicker or other
nodes.  TODO better doco.

=head1 AUTHOR

Philip Gwyn E<lt>gwyn-at-cpan.orgE<gt>

=head1 CREDITS

Based on XUL::Node::Event by Ran Eilam.

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Philip Gwyn.  All rights reserved;

Copyright 2003-2004 Ran Eilam. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=head1 SEE ALSO

perl(1), L<POE::XUL>, L<POE::XUL::ChangeManager>.

=cut

