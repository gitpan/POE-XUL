package POE::XUL::ChangeManager;
# $Id: ChangeManager.pm 654 2007-12-07 14:28:39Z fil $
# Copyright Philip Gwyn 2007.  All rights reserved.
# Based on code Copyright 2003-2004 Ran Eilam. All rights reserved.

#
# POE::XUL::Node and POE::XUL::TextNode will be calling us whenever they
# change attributes or children.
# We keep a list of POE::XUL::State objects that hold all these changes
# so that they may be mirrored in the browser.  To speed things up a lot
# we break POE::XUL::State's encapsulation.
#
# We also maintain a list of all the nodes, available via ->getElementById.
#

use strict;
use warnings;

use Carp;
use HTTP::Status;
use JSON::XS;
use POE::XUL::Logging;
use POE::XUL::State;
use Scalar::Util qw( weaken blessed );

use constant DEBUG => 0;

our $WIN_NAME = 'POEXUL00';

##############################################################
sub new
{
    my( $package ) = @_;

    my $self = bless {
            window      => undef(), 
            states      => {},
            nodes       => {},
            destroyed   => [], 
            prepend     => []
        }, $package;

    $self->build_json;
    return $self;
}

##############################################################
sub build_json
{
    my( $self ) = @_;
    my $coder = JSON::XS->new->space_after( 1 );
    $self->{json_coder} = $coder;
}

##############################################################
sub json_encode
{
    my( $self, $out ) = @_;
    my $json = eval { $self->{json_coder}->encode( $out ) };
    if( $@ ) {
        use Data::Dumper;
        warn "Error encoding JSON: $@\n", Dumper $out;
        my $err = $@;
        $err =~ s/"/\x22/g;
        $json = qq(["ERROR", "", "$err"]);
    }

    DEBUG and 
		do {
			my $foo = $json;
			$foo =~ s/], /],\n/g;
			xdebug "JSON: $foo\n";
            xdebug "JSON size: ", length( $json ), "\n";
        };

    # $json =~ s/], /],\n/g;    
    return $json;
}

##############################################################
sub dispose
{
    my( $self ) = @_;

    foreach my $N ( @{ $self->{destroyed} }, 
                        values %{ $self->{nodes} }, 
                        values %{ $self->{states} } ) {
        next unless defined $N and blessed $N and $N->can( 'dispose' );
        $N->dispose;
    }
    $self->{nodes} = {};
    $self->{destroyed} = [];
    $self->{states} = {};
	$self->{prepend} = [];
}

##############################################################
# Get all changes, send to the browser
sub flush 
{
	my( $self ) = @_;
	local $_;
    # XXX: we could cut down on trafic if we don't flush deleted nodes
    # that are children of a deleted parent
	my @out = ( @{ $self->{prepend} },                      # our stuff
                map( { $_->flush } @{$self->{destroyed}} ), # old stuff
                $self->flush_node( $self->{window} )        # new/changed stuff
              );

    foreach my $win ( @{ $self->{other_windows} || [] } ) {
        push @out, $self->flush_node( $win );
    }
	$self->{destroyed} = [];
	$self->{prepend} = [];
	return \@out;
}

##############################################################
sub flush_node 
{
	my ($self, $node) = @_;
    return unless $node;
    my $state = $self->node_state( $node );
	my @out = $state->flush;
    unless( $state->{is_framify} ) {
        push @out, $self->flush_node( $_ ) foreach $node->children;
    }
	return @out;
}

##############################################################
sub node_state 
{
	my( $self, $node ) = @_;

	return $self->{states}{"$node"} if $self->{states}{"$node"};

    my $is_tn = UNIVERSAL::isa($node, 'POE::XUL::TextNode');

    if( DEBUG ) {
        confess "Not a node: [$node]" unless 
            UNIVERSAL::isa($node, 'POE::XUL::Node') or $is_tn;
    }

    my $state = POE::XUL::State->new;
    $self->{states}{ "$node" } = $state;

    DEBUG and 
        xdebug "$self Created state ", $state->id, " for $node\n";

    $state->{is_textnode} = !! $is_tn;

    $self->register_node( $state->{id}, $node );

    return $state;
}

##############################################################
sub register_window
{
    my( $self, $node ) = @_;
    if( $self->{window} ) {
        xwarn "register_window $node";
        push @{ $self->{other_windows} }, $node;
    }
    else {
        $self->{window} = $node;
    }
}

##############################################################
sub unregister_window
{
    my( $self, $node ) = @_;
    if( $node == $self->{window} ) {
        confess "You aren't allowed to unregister the main window";
    }
    xwarn "unregister_window $node";
    $self->{other_windows} = [
                    grep { $_ != $node } @{ $self->{other_windows}||[] }
                ];
    return;
}

##############################################################
sub register_node
{
    my( $self, $id, $node ) = @_;
    
    if( $self->{nodes}{$id} ) {
        confess "I already have a node id=$id";
    }
    confess "Why you trying to be funny with me?" unless $node;
    # carp "$id is $node";
    $self->{nodes}{ $id } = $node;
    weaken( $self->{nodes}{ $id } );
    return;
}

##############################################################
sub unregister_node
{
    my( $self, $id ) = @_;
    my $node = delete $self->{nodes}{ $id };
    return;
}

##############################################################
sub getElementById
{
    my( $self, $id ) = @_;
    return $self->{nodes}{ $id };
}

##############################################################
sub after_destroy
{
    my( $self, $node ) = @_;
    # Don't use state_node, as it will create the state
    my $state = delete $self->{states}{"$node"};
    my $id;
    if( $state ) {
        $id = $state->{id};
    }
    elsif( $node->can( 'id' ) ) {
        $id = $node->id;
    }
    return unless $id;
    $self->unregister_node( $id, $node );
}

##############################################################
sub after_set_attribute
{
    my( $self, $node, $key, $value ) = @_;
	my $state = $self->node_state($node);

	if ($key eq 'tag') { 
        $state->{tag} = $value; 
        $self->register_window( $node ) if $node->is_window;
    }
	elsif( $key eq 'id' ) {
        return if $state->{id} eq $value;
        DEBUG and xdebug "node $state->{id} is now $value";
        my $old_id = $state->{id};

        $state->set_attribute($key, $value);

        $self->unregister_node( $state->{id}, $node );
        $state->{id} = $value;
        $self->register_node( $state->{id}, $node );
    }
    else {
        $state->set_attribute($key, $value);
    }

}

##############################################################
sub after_remove_attribute
{
    my( $self, $node, $key ) = @_;
    my $state   = $self->node_state( $node );

    $state->remove_attribute( $key );
}

##############################################################
# when node added, set parent node state id on child node state
sub before__add_child_at_index
{
    my( $self, $parent, $child, $index ) = @_;
	my $child_state = $self->node_state( $child );
	$child_state->{parent} = $self->node_state( $parent );
    weaken $child_state->{parent};
	$child_state->{index} = $index;
}

##############################################################
# when node destroyed, update state using set_destoyed
sub before_remove_child
{
    my( $self, $parent, $child, $index ) = @_;
#	my $child       = $parent->_compute_child_and_index($context->params->[1]);
    # return unless $child;
    Carp::croak "Why no index" unless defined $index;
	my $child_state = $self->node_state($child);
	$child_state->is_destroyed( $parent, $index );
	push @{$self->{destroyed}}, $child_state;

    delete $self->{states}{ "$child" };
    $self->unregister_node( $child_state->{id}, $child );
}

##############################################################
# We need for the node to have the same ID as the state
sub after_creation
{
    my( $self, $node ) = @_;
    my $state   = $self->node_state( $node );

    return if $node->getAttribute( 'id' );
    $node->setAttribute( id => $state->{id} );
}


##############################################################
sub after_cdata_change
{
    my( $self, $node ) = @_;
    my $state = $self->node_state( $node );
    $state->{cdata} = $node->{data};
    $state->{is_new} = 1;
}

##############################################################
sub after_framify
{
    my( $self, $node ) = @_;
    my $state = $self->node_state( $node );
    $state->{is_framify} = 1
}




##############################################################
# So that we can detect changes between requests
sub request_start
{
    my( $self ) = @_;
    $self->{responded} = 0;
}

sub request_done
{
    my( $self ) = @_;
    $self->{responded} = 1;
}

##############################################################
sub error_response
{
    my( $self, $resp, $string ) = @_;
    xlog "error_response $resp $string";

    return $self->json_response( $resp, [[ 'ERROR', '', $string]] );
}

##############################################################
sub response
{
    my( $self, $resp ) = @_;
    my $out = $self->flush;
    # xwarn "response = ", 0+@$out;
    $self->json_response( $resp, $out );
}

##############################################################
sub json_response
{
    my( $self, $resp, $out ) = @_;

    if( $self->{responded} ) {
        xcarp "Already responded";
        return;
    }

    my $json;
    if( ref $out ) {
        $json = $self->json_encode( $out );
    }
    else {
        $json = $out;
    }

    DEBUG and 
        xdebug "Response=$json";

    $resp->content_type( 'application/json' ); #; charset=utf8' );
    $self->__response( $resp, $json );
}

##############################################################
sub xul_response
{
    my( $self, $resp, $xul ) = @_;

    $resp->content_type( 'application/vnd.mozilla.xul+xml' );
    $self->__response( $resp, $xul );
}

##############################################################
sub __response
{
    my( $self, $resp, $content ) = @_;

    do {
        # HTTP exptects content-length to be number of octets, not chars
        # The UTF-8 that JSON::XS is producing was screwing up length()
        use bytes;
        $resp->content_length( length $content );
    };
    $resp->content( $content );
    $resp->code( RC_OK );
    $resp->continue();          # but only if we've stoped!

    $self->request_done;
}



##############################################################
sub SID
{
    my( $self, $SID ) = @_;
    push @{ $self->{ prepend } }, $self->build_SID( $SID );
}


##############################################################
sub build_SID
{
    my( $self, $SID ) = @_;
    return POE::XUL::State->make_command_SID( $SID );
}

##############################################################
# Send a boot message to the client
sub Boot
{
    my( $self, $msg ) = @_;
    push @{ $self->{prepend} }, POE::XUL::State->make_command_boot( $msg );
}


##############################################################
# Side-effects for a given event
##############################################################
sub handle_Click 
{
	my( $self, $event ) = @_;
    return;
}

##############################################################
# A textbox was changed
# Uses source, value
sub handle_Change 
{
	my( $self, $event ) = @_;
    DEBUG and 
        xdebug "Change value=", $event->value, " source=", $event->source;
	$event->source->setAttribute( value=> $event->value );
}

##############################################################
sub handle_BoxClick 
{
	my( $self, $event ) = @_;
	my $checked = $event->checked;

    DEBUG and xdebug "Click event=$event source=", $event->source->id;
	# $checked = defined $checked && $checked eq 'true'? 1: 0;
	$event->checked( $checked );
	$event->source->checked( $checked );
}

##############################################################
# A radio button was clicked
# Uses : source, selectedId
sub handle_RadioClick 
{
	my( $self, $event ) = @_;
	my $selectedId = $event->selectedId;

    DEBUG and 
        xdebug "RadioClick source=", 
                   ($event->source->id||$event->source), 
                    " selectedId=$selectedId";
    my $radiogroup = $event->source;
    my $radio = $self->getElementById( $selectedId );

    die "Can't find element $selectedId for RadioClick"
            unless $radio;

    $event->event( 'Click' );
    foreach my $C ( $radiogroup->children ) {
        if( $C == $radio ) {
            $C->setAttribute( 'selected', 1 );
            DEBUG and xdebug "Found $selectedId\n";
            # If there was a Click handler on the Radio, we 
            # revert to the former behaviour of running that handler
            # xdebug "Going to C=$C id=", $C->id;
            $event->bubble_to( $radiogroup );
            $event->__source_id( $C->id );
        }
        elsif( $C->selected ) {
            $C->removeAttribute( 'selected' );
        }
    }
}

##############################################################
# A list item was selected
# Uses: source, selectedIndex
sub handle_Select 
{
	my( $self, $event ) = @_;
    my $menulist = $event->source;
    my $I = $event->selectedIndex;
                              # selecting text in a textbox!
    return unless defined $I and $I ne 'undefined'; 
    my $oI = $menulist->selectedIndex;

    DEBUG and 
        xdebug "Select was=$oI, now=$I";

    $self->Select_choose( $event, $oI, 'selected', 0 );
    $menulist->selectedIndex( $I );
    my $item = $self->Select_choose( $event, $I, 'selected', 1 );

    if( $item ) {
        xdebug "Select $I.label=", $item->label;
        # The event should go to the item first, then the "parent"
        $event->bubble_to( $event->source );
        $event->__source_id( $item->id );
    }
}

##############################################################
# Turn one menuitem on/off
sub Select_choose
{
    my( $self, $event, $I, $att, $value ) = @_;
    my $list = $event->source;
    return unless $list;
    return unless $list->first_child;
    return unless defined $I;

    my $item = $list->getItemAtIndex( $I );
    return unless $item;

    if( $value ) {
        $item->setAttribute( $att, $value );
    }
    else {
        $item->removeAttribute( $att );
    }
    return $item;
}

##############################################################
# User picked a colour
sub handle_Pick 
{
	my( $self, $event ) = @_;
	$event->source->color($self->color);
}

##############################################################
sub Prepend
{
    my( $self, $cmd ) = @_;
    push @{ $self->{prepend} }, $cmd;
    return 0+@{ $self->{prepend} };
}

##############################################################
sub flush_to_prepend
{
    my( $self ) = @_;
    my $out = $self->flush;
    return unless @$out;
    push @{ $self->{prepend} }, @$out;
    return 0+@{ $self->{prepend} };
}

##############################################################
sub timeslice
{
    my( $self ) = @_;
    $self->Prepend( [ 'timeslice' ] );
}

##############################################################
sub popup_window
{
    my( $self, $name, $features ) = @_;
    $name     ||= $WIN_NAME++;
    $features ||= {};
    croak "Features must be a hashref" unless 'HASH' eq ref $features;
    $self->Prepend( [ 'popup_window', $name, $features ] );
}

##############################################################
sub close_window
{
    my( $self, $name ) = @_;
    $self->Prepend( [ 'close_window', $name ] );
}

##############################################################
# Send some instructions to Runner.js.  Or other control of the CM
sub instruction
{
    my( $self, $inst ) = @_;

    my( $op, @param );
    if( ref $inst ) {
        ( $op, @param ) = @$inst;
    }
    else {
        $op = $inst;
    }

    if( $op eq 'flush' ) {                  # flush changes to output buffer
        return $self->flush_to_prepend;
    }
    elsif( $op eq 'empty' ) {               # empty all changes
        return $self->flush;
    }
    elsif( $op eq 'timeslice' ) {           # give up a timeslice
        return $self->timeslice;
    }
    elsif( $op eq 'popup_window' ) {
        return $self->popup_window( @param );
    }
    elsif( $op eq 'close_window' ) {
        return $self->close_window( @param );
    }
    else {
        die "Unknown instruction: $op";
    }
}

1;

__END__

=head1 NAME

POE::XUL::ChangeManager - Keep POE::XUL in sync with the browser DOM

=head1 SYNOPSIS

Not used directly.  See L<POE::XUL> and L<POE::XUL::Event>.

=head1 DESCRIPTION

The ChangeManager is responsible for tracking and sending all changes to a
L<POE::XUL::Node> to the DOM element.  It also handles any side-effects
of a DOM event that was sent from the browser.

There is only one ChangeManager per application.  The application never
accesses the ChangeManager directly, but rather by manipulating
L<POE::XUL::Node>.  

Because there may be multiple application instances within a given process,
the link between L<POE::XUL::Node> and the ChangeManager is handled by
L<POE::XUL::Event>.  Changes to a node B<must> happen within
L<POE::XUL::Event/wrap>.  This is done for you in the initial POE event.  It
B<must> be done explicitly if you chain the initial POE event to furthur POE
events.

=head1 METHODS

There is only one method that will be useful for application writers:

=head2 instruction

    pxInstructions( @instructions );
    $CM->instruction( $inst );
    $CM->instruction( [ $inst, @params ] );

Send instructions to the javascript client library.  Instructions are a HACK
to quickly work around XUL and/or POE::XUL::Node limitations.

C<$inst> may be simply an instruction name, or an arrayref, the first
element of which is the instruction name.

Current instructions are:

=over 4

=item empty

Empties all pending changes, returns the arrayref of those changes.

=item flush

All currently known commands are put into the output buffer.  Combined with
C<timeslice>, it allows some control over the order in which commands are
executed.

=item timeslice

Tells the javascript client library to give up a C<timeslice>.  The idea is
to give the browser time to I<render> any new XBL.  Because it is impossible
to find out when all XBL has finished rendering, the C<timeslice> is handled
by pausing for 5 milliseconds.

To be very useful, you should preceed this with a L</flush>.

=item popup_window

    pxInstruction( [ popup_window => $id, $features ] );

Tell the client library to create a new window.  The new window's name will
be C<$id>.  The new window will be created with the features defined in
C<$features>: 
C<width>, 
C<height>, 
C<location>,
C<menubar>,
C<toolbar>,
C<status>,
C<scrollbars>.
The following features are always C<yes>:
C<resizable>,
C<dependent>.
See L<http://developer.mozilla.org/en/docs/DOM:window.open> for an explanation
of what they mean.

Once the window is opened, it will load C</popup.xul?app=$APP&SID=$SID> (where
C<$APP> is the current application and C<$SID> is the session ID of the
current application instance).  C<popup.xul> will then send a C<connect>
event.  See L<POE::XUL/connect>.

=item close_window

    pxInstruction( [ close_window => $id ] );

Closes the window C<$id>.  This will provoke a C<disconnect> event.
See L<POE::XUL/disconnect>.


=back


=head1 AUTHOR

Philip Gwyn E<lt>gwyn-at-cpan.orgE<gt>

=head1 CREDITS

Based on XUL::Node by Ran Eilam.

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Philip Gwyn.  All rights reserved;

Copyright 2003-2004 Ran Eilam. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=head1 SEE ALSO

perl(1), L<POE::XUL>, L<POE::XUL::Event>.

=cut



