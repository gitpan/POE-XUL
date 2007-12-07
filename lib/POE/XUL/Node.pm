package POE::XUL::Node;
# $Id: Node.pm 654 2007-12-07 14:28:39Z fil $
# Copyright Philip Gwyn 2007.  All rights reserved.
# Based on code Copyright 2003-2004 Ran Eilam. All rights reserved.

use strict;
use warnings;
use Carp;
use Scalar::Util qw( blessed );
use POE::XUL::Constants;
use POE::XUL::TextNode;
use POE::XUL::CDATA;
use Scalar::Util qw( blessed );
use HTML::Entities qw( encode_entities_numeric );

use constant DEBUG => 0;

our $VERSION = '0.05';
our $CM;

my @XUL_ELEMENTS = qw(
      ArrowScrollBox Box Button Caption CheckBox ColorPicker Column Columns
      Deck Description Grid Grippy GroupBox HBox Image Label ListBox
      ListCell ListCol ListCols ListHead ListHeader ListItem Menu MenuBar
      MenuItem MenuList MenuPopup MenuSeparator ProgressMeter Radio
      RadioGroup Row Rows Seperator Spacer Splitter Stack StatusBar
      StatusBarPanel Tab TabBox TabPanel TabPanels Tabs TextBox ToolBar
      ToolBarButton ToolBarSeperator ToolBox VBox Window
);

# my %XUL_ELEMENTS = map { $_ => 1 } @XUL_ELEMENTS;

my @HTML_ELEMENTS = qw( 
    HTML_Pre HTML_H1 HTML_H2 HTML_H3 HTML_H4 HTML_A HTML_Div HTML_Br HTML_Span
);

my @DEFAULT_LABEL = 

my %DEFAULT_ATTRIBUTE = map { $_ => 'label' } qw( 
        caption button menuitem radio listitem
    );
 

my @OTHER_ELEMENTS = qw(
    Script Boot RawCmd pxInstructions
);

my %LOGICAL_ATTS = ( selected => 1 );

# creating --------------------------------------------------------------------

##############################################################
sub import 
{
    my( $package ) = @_;
	my $caller = caller();
	no strict 'refs';
	# export factory methods for each xul element type
	foreach my $sub ( @XUL_ELEMENTS, @HTML_ELEMENTS ) {
        my $tag = lc $sub;
        $tag =~ s/^html_/html:/;
        # delete ${"${caller}::$other"};
		*{"${caller}::$sub"} = sub
			{ return scalar $package->new(tag => $tag, @_) };
	}
	foreach my $other (@OTHER_ELEMENTS) {
        # delete ${"${caller}::$other"}
        *{"${caller}::$other"} = sub
            { return scalar $package->can("$other")->( $package, @_ ) };
    }

	# export the xul element constants
	foreach my $constant_name (@POE::XUL::Node::Constants::EXPORT) { 
        *{"${$caller}::$constant_name"} = *{"$constant_name"} 
    }
}

##############################################################
sub new 
{
	my ($class, @params) = @_;
	my $self = bless {attributes => {}, children => [], events => {}}, $class;


    if( DEBUG and not $CM and $INC{'POE/XUL/ChangeManager.pm'} ) {
        Carp::cluck "Building a POE::XUL::Node, but no ChangeManager avaiable";
    }

	while (my $param = shift @params) {
		if( ref $param ) {
            $self->appendChild( $param );
        }
		elsif( $param =~ /\s/ or 0==@params ) {
            $self->defaultChild( $param );
        }
		elsif ($param eq 'textNode' ) { 
            $self->appendChild( shift @params );
        }
		elsif ($param =~ /^[a-z]/) { 
            $self->set_attribute( $param => shift @params );
        }
		elsif ($param =~ /^[A-Z]/) { 
            $self->attach($param => shift @params) 
        }
		else { 
            croak "unrecognized param: [$param]" 
        }
	}
    $CM->after_creation( $self ) if $CM;

	return $self;
}

##############################################################
sub Script {
    my $class = shift;
    # warn "class=$class";
    # warn "script=", join "\n", @_;
    my $cdata = POE::XUL::CDATA->new( join "\n", @_ );
    return $class->new( tag=>'script', type=>'text/javascript', $cdata );
}

##############################################################
# Boot message
sub Boot
{
    my( $class, $msg ) = @_;
    if( $CM ) {
        $CM->Boot( $msg );
    }
    return;
}

##############################################################
# Send a raw command to Runner.js
sub RawCmd
{
    my( $class, $cmd ) = @_;
    if( $CM ) {
        $CM->Prepend( $cmd );
    }
    return;
}

##############################################################
# Instructions to Runner.js, via ChangeManager
sub pxInstructions
{
    my( $self, @inst ) = @_;
    unless( $CM ) {
        unless( $INC{ 'Test/More.pm' } ) {
            carp "There is no ChangeManager.  Instructions ignored.";
        }
        return;
    }

    my $rv;
    foreach my $inst ( @inst ) {
        $rv = $CM->instruction( $inst );
    }
    return $rv;
}


##############################################################
sub build_text_node
{
    my( $self, $text ) = @_;
    my $textnode = POE::XUL::TextNode->new;

    $textnode->nodeValue( $text );
    return $textnode;
}
*createTextNode = \&build_text_node;


##############################################################
sub textNode
{
    my( $self, $text ) = @_;

    my $old;
    foreach my $C ( $self->children ) {
        next unless $C->isa( 'POE::XUL::TextNode' );
        $old = $C;
    }

    unless( 2==@_ ) {
        return unless $old;
        return $old->nodeValue;
        return;
    }

    if( $old and ref $text ) {
        $self->replaceChild( $text, $old );
        return $text->nodeValue if blessed $text;
        return $text;
    }
    elsif( $old ) {
        return $old->nodeValue( $text );
    }
    else {
        return $self->appendChild( $text )->nodeValue;
    }
}


##############################################################
sub getItemAtIndex
{
    my( $self, $index ) = @_;
    return if not defined $index or $index < 0;

    if( $self->tag eq 'menulist' ) {
        $self = $self->firstChild;
    }

    my $N = 0;
    foreach my $I ( $self->children ) {
        my $t = $I->tag;
        next unless $t eq 'listitem' or $t eq 'menuitem';
        return $I if $N == $index;
        $N++;
    }
    return;
}
*get_item = \&getItemAtIndex;

# attribute handling ----------------------------------------------------------

##############################################################
sub attributes    
{ 
    my( $self ) = @_;
    return %{$self->{attributes}} if wantarray;
    return $self->{attributes};
}

##############################################################
sub get_attribute 
{ 
    my( $self, $key ) = @_;
    return $self->{attributes}{$key};
}
*getAttribute = \&get_attribute;


##############################################################
sub set_attribute 
{
    my( $self, $key, $value ) = @_;
    if( $key eq 'tag' ) {
        $value = lc $value;
        $value =~ s/^html_/html:/;
    }

    if( $LOGICAL_ATTS{ $key } ) {
        unless( $value ) {
            $self->remove_attribute( $key );
            return;     # TODO: after_set_attribute needs to be called, no?
        }
        $value = $value ? 'true' : 'false';
        
    }

#    if( $key eq 'selectedIndex' ) {
#        carp $self->id, ".$key=$value";
#    }

    $self->{attributes}{$key} = $value;
    $CM->after_set_attribute( $self, $key, $value ) if $CM;
    return $value;
}
*setAttribute = \&set_attribute;

##############################################################
sub remove_attribute 
{ 
    my( $self, $key ) = @_;
    croak "You may not remove the tag attribute" if $key eq 'tag';
    $CM->after_remove_attribute( $self, $key ) if $CM;
    delete $self->{attributes}{ $key }; 
}
*removeAttribute = \&remove_attribute;

##############################################################
sub is_window
{ 
    my( $self ) = @_;
    return( ($self->{attributes}{tag}||'') eq 'window');
}

##############################################################
*id = __mk_accessor( 'id' );
#*tag = __mk_accessor( 'tag' );
#*textNode = __mk_accessor( 'textNode' );

sub __mk_accessor
{
    my( $tag ) = @_;
    return sub {
        my( $self, $value ) = @_;
        if( @_ == 2 ) {
            return $self->set_attribute( $tag, $value );
        }
        else {
            return $self->{attributes}{$tag};
        }
    }
}

##############################################################
sub AUTOLOAD {
	my( $self, $value ) = @_;
	my $key = our $AUTOLOAD;
	return if $key =~ /DESTROY$/;
	$key =~ s/^.*:://;
#    Carp::confess $key;
    if( $key =~ /^[a-z]/ ) {
        if( @_ == 1 ) {
            return $self->get_attribute( $key );
        }
        else {
            return $self->set_attribute( $key, $value );
        }
    }
    elsif( $key =~ /^[A-Z]/ ) {
        $self->add_child( __PACKAGE__->new(tag => $key, @_[ 1..$#_ ] ) );
    }
    croak __PACKAGE__. "::AUTOLOAD cannot find method $key";
}

##############################################################
sub hide 
{
    my( $self ) = @_;
    my $css = $self->style||'';
    $css .= "display: none;";
    $self->style( $css );
}

##############################################################
sub show
{
    my( $self ) = @_;
    my $css = $self->style||'';
    $css =~ s/display: none;//;
    $self->style( $css );
}



##############################################################
# Turn a node into an iframe that loads itself
# This is a major mess.
# ChangeManager will use State to create the JSON command
# POEXUL_Runner then tells POEXUL_Application to framify
# POEXUL_Application replaces the element with a new iframe
# iframe.src = "/xul?type=XUL-from&source_id=OUR-ID
# POE::Component::XUL and POE::XUL::Controler then send us over as_xml
sub framify
{
    my( $self ) = @_;
    $CM->after_framify( $self ) if $CM;
}

##############################################################
# DOM-like window.close()
sub close
{
    my( $self ) = @_;
    croak qq(Can't locate object method "close" via package ").
                    ref( $self ) . qq(") unless $self->tag eq 'window';
    $CM->unregister_window( $self ) if $CM;
}

# compositing -----------------------------------------------------------------

sub children    { wantarray? @{shift->{children}}: shift->{children} }
sub child_count { scalar @{shift->{children}} }
sub hasChildNodes { return 0!= scalar @{shift->{children}} }
sub first_child { shift->{children}->[0] }
*firstChild     = \&first_child;
sub get_child   { shift->{children}->[pop] }
sub last_child { shift->{children}->[-1] }
*lastChild     = \&last_child;

##############################################################
sub add_child {
	my ($self, $child, $index) = @_;
    # This is a huge speed up, but breaks the Aspect stuff
#    unless( defined $index ) {
#        push @{$self->{children}}, $child;
#        return $child;
#    }
	my $child_count = $self->child_count;
	$index = $child_count unless defined $index;
	croak "index out of bounds: [$index:$child_count]"
		if ($index < 0 || $index > $child_count);

    if( $self->{children}[$index] ) {
        $self->remove_child( $index );
    }

	$self->_add_child_at_index($child, $index);
	return $child;
}
sub appendChild
{
    my( $self, $child ) = @_;
    $child = $self->createTextNode( $child ) unless ref $child;
	my $index = $self->child_count;
	$self->_add_child_at_index( $child, $index );
}

sub defaultChild
{
    my( $self, $text ) = @_;
    my $d_att = $DEFAULT_ATTRIBUTE{ lc $self->{attributes}{tag} || '' };
    if( $d_att ) {
        $self->setAttribute( $d_att => $text );
        return;
    }
    
    my $child = $self->createTextNode( $text );
	my $index = $self->child_count;
	$self->_add_child_at_index( $child, $index );
}

##############################################################
sub replaceChild {
	my ($self, $new, $old) = @_;

	my ($oldNode, $index) = $self->_compute_child_and_index($old);
    $CM->before_remove_child( $self, $oldNode, $index ) if $CM;
	splice @{$self->{children}}, $index, 1, $new;
    $CM->before__add_child_at_index( $self, $new, $index ) if $CM;
	$old->dispose;
	return $self;
}

##############################################################
sub remove_child {
	my ($self, $something) = @_;

	my ($child, $index) = $self->_compute_child_and_index($something);

    unless( $child and $index < @{ $self->{children} } ) {
        Carp::carp "Attempt to remove an unknown child node";
        return;
    }

    # warn "remove_child id=", $child->{attributes}{id};
    $CM->before_remove_child( $self, $child, $index ) if $CM;
	splice @{$self->{children}}, $index, 1;
	$child->dispose if blessed $child;
	return $self;
}

*removeChild = \&remove_child;

##############################################################
sub get_child_index 
{
	my ($self, $child) = @_;
	my $index = 0;
	my @children = @{$self->{children}};
	$index++ until $index > @children || $child eq $children[$index];
	croak 'child not in parent' unless $children[$index] eq $child;
	return $index;
}

##############################################################
# computes child and index from child or index
sub _compute_child_and_index 
{
	my ($self, $something) = @_;
	my $is_node = ref $something;
	my $child   = $is_node? $something: $self->get_child($something);
	my $index   = $is_node? $self->get_child_index($something): $something;
	return wantarray? ($child, $index): $child;
}

sub _add_child_at_index {
	my ($self, $child, $index) = @_;
    $CM->before__add_child_at_index( $self, $child, $index ) if $CM;
    if( $index > $#{ $self->{children} } ) {
        push @{ $self->{children} }, $child;
    }
    else {
        splice @{$self->{children}}, $index, 0, $child;
    }
	return $child;
}

# event handling --------------------------------------------------------------

sub attach { 
    my( $self, $name, $listener ) = @_;
    $self->{events}->{ $name } = $listener
}

sub detach {
	my ($self, $name) = @_;
	my $listener = delete $self->{events}->{$name};
	croak "no listener to detach: $name" unless $listener;
}	

sub event {
	my ($self, $name) = @_;
	my $listener = $self->{events}->{ $name };
	return $listener;
}

# disposing ------------------------------------------------------------------

# protected, used by sessions and by parent nodes to free node memory 
# event handlers could cause reference cycles, so we free them manually
sub dispose {
	my $self = shift;
	$_->dispose for grep { blessed $_ } $self->children;
	delete $self->{events};
}
*destroy = \&dispose;

sub is_destroyed { !shift->{events} }

sub DESTROY
{
    my( $self ) = @_;
    # carp "DESTROY ", $self->id;
    $CM->after_destroy( $self ) if $CM;
}



#######################################################################
sub as_xml {
	my $self       = shift;
	my $level      = shift || 0;
	my $tag        = lc $self->tag;
    $tag =~ s/_/:/;
	my $attributes = $self->attributes_as_xml;
	my $children   = $self->children_as_xml($level + 1);
#	my $indent     = $self->get_indent($level);
    return qq[<$tag$attributes${\( $children? ">$children</$tag": '/' )}>];
}

sub attributes_as_xml {
	my $self       = shift;
	my %attributes = $self->attributes;
	my $xml        = '';
    
    foreach my $k ( keys %attributes ) {
        next if defined $attributes{ $k };
        warn $self->id."/$k is undef";
        $self->$k( '' );
    }
	$xml .= qq[ $_='${\( encode_entities_numeric( $self->$_, "\x00-\x1f<>&\'\x80-\xff" ) )}']
		for grep { $_ ne 'tag' and $_ ne 'textNode' } keys %attributes;
#    die $xml if $xml =~ /\n/;
	return $xml;
}

sub children_as_xml {
	my $self   = shift;
	my $level  = shift || 0;
#	my $indent = $self->get_indent($level);
	my $xml    = '';
#	$xml .= qq[\n$indent${\( $_->as_xml($level) )}] for $self->children;
	$xml .= qq[${\( blessed $_ ? $_->as_xml($level) : $_ )}] for $self->children;
	return $xml;
}

sub get_indent { ' ' x (3 * pop) }

1;

__END__

=head1 NAME

POE::XUL::Node - XUL element

=head1 SYNOPSIS

  use POE::XUL::Node;

  # Flexible way of creating an element
  my $box = POE::XUL::Node->new( tag => 'HBox', 
                                 Description( "Something" ),
                                 class => 'css-class',
                                 style => $css,
                                 Click => $poe_event  
                               );

  # DWIM way
  $window = Window(                            # window with a header,
     HTML_H1(textNode => 'a heading'),         # a label, and a button
     $label = Label(FILL, value => 'a label'),
     Button(label => 'a button'),
  );

  # attributes
  $window->width( 800 );
  $window->height( 600 );

  $label->value('a value');
  $label->style('color:red');
  print $label->flex;

  # compositing
  print $window->child_count;                  # prints 2
  $window->Label(value => 'another label');    # add a label to window
  $window->appendChild(Label);                 # same but takes child as param
  $button = $window->get_child(1);             # navigate the widget tree
  $window->add_child(Label, 0);                # add a child at an index

  # events
  $window->Button(Click => sub { $label->value('clicked!') });
  $window->MenuList(
     MenuPopup(map { MenuItem( label => "item #$_", ) } 1..10 ),
     Select => sub { $label->value( $_[0]->selectedIndex ) },
  );

  # disposing
  $window->removeChild($button);                # remove child widget
  $window->remove_child(1);                     # remove child by index

=head1 DESCRIPTION

POE::XUL::Node is a DOM-like object that encapsulates a XUL element.
It uses L<POE::XUL::ChangeManager> to make sure all changes are mirrored
in the browser's DOM.


=head2 Elements

To create a UI, an application must create a C<Window> with some elements in
it.  Elements are created by calling a function or method named after their
tag:

  $button = Button;                           # orphan button with no label
  $box->Button;                               # another, but added to a box
  $widget = POE::XUL::Node->new(tag => $tag); # using dynamic tag

After creating a widget, you must add it to a parent. The widget will
show when there is a containment path between it and a window. There are
multiple ways to set an elements parent:

  $parent->appendChild($button);              # DOM-like
  $parent->replaceChild( $old, $new );        # DOM-like
  $parent->add_child($button);                # left over from XUL-Node
  $parent->add_child($button, 1);             # at an index
  $parent->Button(label => 'hi!');            # create and add in one shot
  $parent = Box(style => 'color:red', $label);# add in parent constructor


Elements can be removed from the document by removing them 
from their parent:

  $parent->removeChild($button);           # DOM-like
  $parent->remove_child(0);                 # index
  $parent->replaceChild( $old, $new );        # DOM-like


Elements have attributes. These can be set in the constructor, or via
a method of the same name:

  my $button = Button( value => 'one button' );
  $button->value('a button');
  print $button->value;                       # prints 'a button'


You can configure all attributes, event handlers, and children of a
element, in the constructor. There are also constants for commonly used
attributes. This allows for some nice code:

  Window( SIZE_TO_CONTENT,
     Grid( FLEX,
        Columns( Column(FLEX), Column(FLEX) ),
        Rows(
           Row(
              Button( label => "cell 1", Click => $poe_event ),
              Button( label => "cell 2", Click => $poe_event ),
           ),
           Row(
              Button( label => "cell 3", Click => $poe_event ),
              Button( label => "cell 4", Click => $poe_event ),
           ),
        ),
     ),
  );

Check out the XUL references (L<http://developer.mozilla.org/en/docs/XUL>)
for an explanation of available elements and their attributes.




Events are removed with the L</detach> method:

    $button->detach( 'Click' );



=head2 Events

Elements receive events from their client halves, and pass them on to
attached listeners in the application. You attach a listener to a widget
so:

  # listening to existing widget
  $textbox->attach( Change => sub { print 'clicked!' } );

  # listening to widget in constructor
  TextBox( Change => $poe_event );

You attach events by providing an event name and a listener. Possible
event names are C<Click>, C<Change>, C<Select>, and C<Pick>. Different
widgets fire different events. These are listed in L<POE::XUL::Event>.

Listener are either the name of a POE event, or a callbacks that receives a
single argument: the event object (L<POE::XUL::Event>).  POE events are
called on the application session, NOT the current session when an event is
defined.  If you want to post to another session, use
L<POE::Session/callback>.

You can query the Event object for information about the event: C<name>,
C<source>, and depending on the event type: C<checked>, C<value>, C<color>,
and C<selectedIndex>.

Here is an example of listening to the C<Select> event of a list box:

  Window(
     VBox(FILL,
        $label = Label(value => 'select item from list'),
        ListBox(FILL, selectedIndex => 2,
           (map { ListItem(label => "item #$_") } 1..10),
           Select => sub {
              $label->value
                 ("selected item #${\( shift->selectedIndex + 1 )}");
           },
        ),
     ),
  );

Events are removed with the L</detach> method:

    $button->detach( 'Click' );

=head2 XUL-Node API vs. the Javascript XUL API

The XUL-Node API is different in the following ways:

=over 4

=item *

Booleans are Perl booleans.

=item *

All nodes must have an C<id> attribute.  If you do not specify one, it will
be automatically generated by POE::XUL::Node.

=item *

There is little difference between attributes, properties, and methods. They
are all attributes on the L<POE::XUL::Node> object.  However, the javascript
client library handles them differently.

This means that to call a method or a property, you have to specify at least
one parameter:

    $node->blur( 0 );           # Equiv to node.blur() in JS

=item *

While all attribute and properties are mirrored from the Perl object to the
DOM object, only a select few are mirrored back (C<value>, C<selected>,
C<selectedIndex>).

=item *

There exist constants for common attribute key/value pairs. See
L<POE::XUL::Node>.

=back

=head1 ELEMENT CONSTRUCTORS

To make life funner, a bunch of constructor functions have been defined
for the most commonly used elements.  These functions are exported into
any package that uses POE::XUL::Node.

=head2 XUL Elements

ArrowScrollBox, Box, Button, Caption, CheckBox, ColorPicker, Column, Columns, 
Deck, Description, Grid, Grippy, GroupBox, HBox, Image, Label, ListBox, 
ListCell, ListCol, ListCols, ListHead, ListHeader, ListItem, Menu, MenuBar, 
MenuItem, MenuList, MenuPopup, MenuSeparator, ProgressMeter, Radio, 
RadioGroup, Row, Rows, Seperator, Spacer, Splitter, Stack, StatusBar, 
StatusBarPanel, Tab, TabBox, TabPanel, TabPanels, Tabs, TextBox, ToolBar, 
ToolBarButton, ToolBarSeperator, ToolBox, VBox, Window.

It is of course possible to create any other XUL element with:

    POE::XUL::Node->new( tag => $tag );


=head2 HTML Elements

HTML_Pre, HTML_H1, HTML_H2, HTML_H3, HTML_H4, HTML_A, HTML_Div, HTML_Br, 
HTML_Span.

It is of course possible to create any other HTML element with:

    POE::XUL::Node->new( tag => "html:$tag" );


=head1 SPECIAL ELEMENTS

There are 4 special elements:

=head2 Script

    Script( $JS );

Creates a script element, with C<type="text/javascript">, and a single
L<POE::XUL::CDATA> child.  The client library will C<eval()> the script.

=head2 Boot

    Boot( $text );

Sends the boot command to the client library.  Currently, the client library 
calls C<$status.title( $text );>, if the C<$status> object exists.  Your
application must create C<$status>.

=head2 RawCmd

    RawCmd( \@cmd );

Allows you to send a raw command to the Javascript client library.  Use at
your own risk.

=head2 pxInstructions

    pxInstructions( @instructions );

Send instructions to the ChangeManager.  This is a slightly higher-level
form of L</RawCmd>.  Its presence indicates the immaturity of POE::XUL as a
whole.  These instructions are subject to change/removal in the future.

L<@instructions> is an array instructions for the ChangeManager.  
See L<POE::XUL::ChangeManager/instrction> for details.


=head1 METHODS

=head2 createTextNode
=head2 textNode

=head2 children
=head2 child_count
=head2 hasChildNodes

=head2 add_child

    $parent->add_child( $node, $index );

=head2 appendChild

    $parent->appendChild( $node );

=head2 firstChild / first_child

    my $node = $parent->firstChild;

=head2 get_child

    my $node = $parent->get_child( $index );

=head2 getItemAtIndex / get_item

    my $node = $menu->getItemAtIndex( $index );

Like L</get_child>, but works for C<menulist> and C<menupopup>.

=head2 lastChild / last_child

    my $node = $parent->lastChild;

=head2 removeChild / remove_child

    $parent->removeChild( $node );
    $parent->removeChild( $index );

=head2 replaceChild

    $parent->replaceChild( $old, $new );

=head2 attributes

    my %hash = $node->attributes;
    my $hashref = $node->attributes;

Note even if you manipulate C<$hashref> directly, changes will not be
mirrored in the DOM node.

=head2 getAttribute / get_attribute

    my $value = $node->getAttribute( $name );

=head2 setAttribute / set_attribute

    $node->setAttribute( $name => $value );

=head2 removeAttribute / remove_attribute

    $node->removeAttribute( $name );



=head2 hide

    $node->hide;

Syntatic sugar that adds C<display: none> to the style attribute.

=head2 show

    $node->show;

Syntatic sugar that removes C<display: none> from the style attribute.

=head2 close

Close a sub-window.  Obviously may only be called on a Window element.

=head2 attach

    $node->attach( $Event => $poe_event );

=head2 detach

    $node->detach( $Event );

=head2 event

    my $listener = $node->event( $Event );

=head2 dispose / distroy

Calls C<dispose> on all the child nodes, and drops all events.

=head2 as_xml

Returns this element and all its child elements as an unindented XML string.
Useful for debuging.

=head1 LIMITATIONS

=over 4

=item *

Some elements are not supported yet: tree, popup.

=item *

Some DOM features are not supported yet:

  * multiple selections
  * node disposal
  * color picker will not fire events if type is set to button
  * equalsize attribute will not work
  * menus with no popups may not show

=back


=head1 SEE ALSO

L<POE::XUL>.
L<POE::XUL::Event> presents the list of all possible events.

L<http://developer.mozilla.org/en/docs/XUL>
has a good XUL reference.


=head1 AUTHOR

Philip Gwyn E<lt>gwyn-at-cpan.orgE<gt>

=head1 CREDITS

Based on work by Ran Eilam.

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Philip Gwyn.  All rights reserved;

Copyright 2003-2004 Ran Eilam. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
