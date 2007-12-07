# Copyright 2007 by Philip Gwyn.  All rights reserved;

our $VERSION = '0.0200';

__END__

=head1 NAME

POE::XUL - Create remote XUL application in POE

=head1 SYNOPSIS

    use POE;
    use POE::Component::XUL;

    POE::Component::XUL->spawn( { apps => {   
                                        Test => 'My::App',
                                        # ....
                                } } );
    $poe_kernel->run();

    ##########
    package My::App;
    use POE::XUL::Node;

    sub spawn
    {
        my( $package, $event ) = @_;
        my $self = bless { SID=>$event->SID }, $package;
        POE::Session->create(
            object_states => [ $self => 
                [ qw( _start boot Click shutdown other_state ) ] ],
        );
    }

    #####
    sub _start {
        my( $self, $kernel ) = @_[ OBJECT, KERNEL ];
        $kernel->alias_set( $self->{SID} );
    }


    #####
    sub boot {
        my( $self, $kernel, $event ) = @_[ OBJECT, KERNEL, ARG0 ];
        $self->{D} = Description( "do the following" );
        $self->{W} = Window( HBox( $self->{D}, 
                                   Button( label => "click me", 
                                           Click => 'Click' ) ) );
        $event->finish;
    }

    #####
    sub Click {
        my( $self, $kernel, $event ) = @_[ OBJECT, KERNEL, ARG0 ];
        $event->done( 0 );
        $kernel->yield( 'other_state', $event );
    }

    sub other_state {
        my( $self, $kernel, $event ) = @_[ OBJECT, KERNEL, ARG0 ];
        $event->wrap( sub {
                $self->{D}->textNode( 'You did it!' );
                $self->{W}->firstChild->appendChild( $self->{B2} );
            } );
        $event->finished;
    }

    #####
    sub shutdown {
        my( $self, $kernel, $SID ) = @_[ OBJECT, KERNEL, ARG0 ];
        $kernel->alias_remove( $self->{SID} );
    }

=head1 DESCRIPTION

POE::XUL is a framework for creating remote XUL applications with POE.  It
includes a web server, a Javascript client library for Firefox and a widget
toolkit in Perl.

POE::XUL uses mirror objects.  That is, each XUL node exists as a Perl
object in the server and as a DOM object in the client.  A ChangeManager on
the server and the javascript client library are responsible for keeping the
objects in sync.  Note that while all node attribute changes in the server
are mirrored in the client, only the most important attributes (C<value>,
C<selected>, ...) are mirrored from the client to the server.

POE::XUL currently uses a syncronous, event-based model for updates.  This
will be changed to an asyncronous, bidirectional model (comet) soon, I hope.

XUL is only supported by browsers from the mozilla project (Firefox and
xulrunner).  While this limits POE::XUL's use for general web application,
POE::XUL would make for some very powerful intranet apps.

B<NOTE>: POE::XUL should be considered alpha quality.  While I have apps
based on POE::XUL in production, the documentation is probably incomplete
and this API will probably change.

POE::XUL is a fork of Ran Eilam's XUL::Node.  POE::XUL permits the async use
of POE events during event handling.  It also removes the use of the
excesively slow Aspect and the heavy XML wire protocol.  L<POE::XUL::Node>'s
API is closer to that of a DOM element.  POE::XUL has rudimentary support
for sub-windows.  XUL::Node's (IMHO) dangerous autoloading of
XUL::Node::Applications packages has been removed.

=head2 The application

POE::XUL applications generaly have one POE session per application
instance.  The POE session is created when a boot request is recieved from
the client.  The session then must handle a 'boot' event, where-in it
creates a L<Window> node and its children nodes.  The session is kept
active, handling the user events it has defined, until the users stops using
it, that is a period of inactivity.  The session is then sent a 'timeout'
event followed by a 'shutdown' event.

Because every application stays in-memory for the entire duration of the
application, you will probably want to set up a HTTP proxy front-end with
process affinity.

It might also be possible to have multiple L<POE::XUL> applications with-in
one session.  Tests needed.

=head2 XUL nodes

If you are not familiar with XUL, you should read
L<http://www.xulplanet.com/tutorials/xultu/intro.html>.  You should also
keep L<http://developer.mozilla.org/en/docs/XUL> handy.

XUL nodes are created and manipulated with L<POE::XUL::Node>. Each
application must create a C<Window> node and all its children.

=head2 Layers

There are many layers POE::XUL.  Maybe too many.

First off, the browser or xulrunner loads C<start.xul?AppName>, which loads
the Javascript client library and any necessary CSS.  The client library
sends a C<boot> event to the server using C<prototype.js>. 
L<POE::Component::XUL> handles HTTP requests in the server.  For a boot
request, it creates a L<POE::XUL::ChangeManager> for the application which
is used by the event to capture any changes to L<POE::XUL::Node>.  The
controler then spawns the application and calls its C<boot> state.  All
nodes created during the boot request will have been noticed by the change
manager.  These nodes are converted into JSON instructions by the
ChangeManager, which are sent as the HTTP response. The JS client library
decodes the JSON instructions, populating the XUL DOM tree with the new
nodes.

The user then interacts with the XUL DOM, which will provoke DOM events.
These events are turned into an AJAX request by the JS client library. 
L<POE::Component::XUL> decodes these requets and hands them to the
L<POE::XUL::Controler>.  The Controler creates and populates an
L<POE::XUL::Event>.  The Event will get the ChangeManager to handle any
event I<side-effects>, such as setting C<value> of the target node.  The
Event will then call any user-defined callbacks or postbacks.  When the
event is finished, the ChangeManager converts any changes to the
POE::XUL::Nodes to JSON instructions, which are sent as the HTTP response.
The JS client library decodes the JSON instructions, modifying the XUL DOM
tree as necessary.

Understand?  Myabe the following diagram will help:

                                        User
                                         |
    Firefox or xulrunner              DOM Node
                                         |
                                  +------+------+
                                 /               \
    JS client library          Event           Response
                                \/                /\
    HTTP/AJAX                 Request            JSON
                                \/                /\
    POE::Component::XUL       decode              ||
    POE::XUL::Controler       create Event        ||
    POE::XUL::Event           side effects       flush
    POE::XUL::ChangeManger    record changes -> convert


=head2 XBL

You are encouraged to create your own XUL nodes with XBL.  To do so, you
will need a custom C<start.xul> that loads the CSS that defines your XBL. 
To create the nodes with C<POE::XUL::Node>

=head1 POE::XUL EVENTS

The life of an application is controled by 1 package method and 2 or more
POE events.

=head2 spawn

    sub spawn {
        my ( $package, $event ) = @_;
        my $SID = $event->SID;
        POE::Session->create( #... );
    }

Not actually an event!  This is a package method that will be called to
create a new application instance.  It B<must> set the session's alias
to the application's SID, available via C<$event-E<gt>SID>.  

All furthur communication with the application instance happens by 
posting POE events to the SID.

=head2 boot

    sub boot {
        my( $self, $event ) = @_[ OBJECT, ARG0 ];
        # create a POE::XUL Window and other nodes.
    }

Once the application's session has been spawned, a C<boot> event is sent.
This event B<must> create at least C<Window> with L<POE::XUL::Node>.  It
should also create all necessary child nodes.

=head2 timeout

    sub timeout {
        my( $self, $SID ) = @_[ OBJECT, ARG0 ];
        # ....
    }

Called after the application has been inactive (no events from the client)
for longer then the C<timeout> value.  No action is required.

=head2 shutdown

    sub timeout {
        my( $self, $kernel, $SID ) = @_[ OBJECT, KERNEL, ARG0 ];
        $kernel->alias_remove( $SID );
        # ....
    }

Posted when it is time to delete an application instance.  This is either
when the instance has timed-out, or when the server is shutting down.

The session is expected to remove all references (aliases, files, extrefs,
...) so that the POE kernel may GC it.

=head1 SUB-WINDOWS

B<SUB-WINDOW SUPPORT IS STILL EXPERIMENTAL.>  As such, it could very well
change in a future version.

Sub-window support is complicated because C<POE::XUL> is synchronous,
event-based.  This means that changes to a node must be done during an
event that is dispatched from the relevant window.

=head2 connect

    sub connect {
        my( $self, $event ) = @_[ OBJECT, ARG0 ];
        # create a POE::XUL Window and child nodes.
    }

Posted from a new sub-window when it  has been created.  This is similar to
C<boot>, in that you B<must> create a L<POE::XUL::Node> Window and child
nodes.

=head2 disconnect

    sub disconnect {
        my( $self, $event ) = @_[ OBJECT, ARG0 ];
        # Delete the POE::XUL Window and its child nodes.
        # But don't send those instructions to the main window
        pxInstruction( 'empty' );
    }

Posted from the main window when a sub-window is closed.  You should
delete all nodes related to the sub-window.  But, because the event


=head1 DOM EVENTS

After the C<boot> event, further interaction happens via callback events
that you defined on your nodes.  A callback may be a coderef or a POE event.

Note that L<POE::XUL> events to not bubble like DOM events do.


=head2 Click

The most important event.  Happens when a user clicks on a button.  The
application will react accordingly.  See L<POE::XUL::Event/Click> for more
details.

=head2 Change

A less important event, C<Change> is called when the value of a TextBox has
changed.  The application does not have to update the source node's value;
this is a side-effect handled by the ChangeManager.  See 
L<POE::XUL::Event/Change> for more
details.

=head2 Select

See L<POE::XUL::Event/Select> for more details.

=head2 Pick

Called when the users selects a colour in a Colorpicker, Datepicker or other
nodes.  See L<POE::XUL::Event/Pick> for more details.

=head2 POE::XUL::Event and POE::XUL::ChangeManager

Only changes that are wrapped in an Event will be seen by the ChangeManager
and be mirrored in the client. L<POE::XUL::Event> will wrap the initial
event and call it with L<POE::Kernel/call>.  If you wish to post further POE
events, you must set the Event's done to 0, and wrap any node changes with
L<POE::XUL::Event/wrap>.  You must call L<POE::XUL::Event/finished> to
complete the request.

L<POE::XUL::Event/wrap> also provides error handling;  if your code dies,
the error message will be displayed in the browser.

=head1 TODO

POE::XUL is still a work in progress.  Things that aren't done:

=over 4

=item Keepalive

If a keepalive request was sent ever X seconds, the application timeout
could be much shorter, as we would know sooner a browser window was closed.

=item Sub-windows

Better handling of sub-windows is needed. Events should be disassociated
from windows.  Nodes should be associated with windows.  Changes to a node
should be mirrored in the relevante window, regardless of where the event
originated.

=item Comet

Move from a synchronous event-based model to a full, bi-directional,
asynchronous model using Comet (L<http://cometd.com/>).  Comet would also
act as a keepalive.

=item Better XUL coverage

There are no tests for E<lt>colorpickerE<gt>, E<lt>datepickerE<gt>, 
E<lt>toolbar<gt>, E<lt>listbox<gt>, E<lt>tab<gt> and more.

=item POE::XUL::Application

A base class that would handle most of the simple house-keeping.

=back


=head1 AUTHOR

Philip Gwyn E<lt>gwyn-at-cpan.orgE<gt>

=head1 CREDITS

Based on XUL::Node by Ran Eilam, POE::Component::XUL by David Davis, and of
course, POE, by the illustrious Rocco Caputo.

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Philip Gwyn.  All rights reserved;

Copyright 2005 by David Davis and Teknikill Software;

Copyright 2003-2004 Ran Eilam. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=head1 SEE ALSO

perl(1), L<POE::XUL::Node>, L<POE::XUL::Event>, L<POE::XUL::Controler>.

=cut

