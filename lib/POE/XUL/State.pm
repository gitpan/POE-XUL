package POE::XUL::State;
# $Id: State.pm 596 2007-11-14 03:36:54Z fil $
# Copyright Philip Gwyn 2007.  All rights reserved.
# Based on code Copyright 2003-2004 Ran Eilam. All rights reserved.

#
# ROLE: Track all the changes to a node so they may be sent to the browser.
# All normal responses are generated here, either by ->flush.  Or in
# some cases calling the make_command directly.
#
# {buffer} is list of attribute key/value pairs set on state since last flush
# {is_new} is true if we have never been flushed before
# {is_destroyed} true after node has been destroyed
#

use strict;
use warnings;
use Carp;

use constant DEBUG => 0;

our $ID = 0;


##############################################################
sub new 
{ 
    my( $package ) = @_;
    my $self = bless {
            buffer => [], 
            is_new => 1, 
            is_destroyed => 0, 
            is_textnode => 0
        }, $package;

    $self->{orig_id} = $self->{id} = 'PX' . $ID++;

    return $self;
}

##############################################################
sub flush 
{
	my( $self ) = @_;
	my @out = $self->as_command;
	$self->set_old;
	$self->clear_buffer;
	return @out;
}

# command building ------------------------------------------------------------

sub as_command {
	my $self = shift;

	my $is_new       = $self->{is_new};
	my $is_destroyed = $self->{is_destroyed};

    # TODO: this is probably a bad idea
	return if $is_new && $is_destroyed;

    if( $is_destroyed ) {
        return $self->get_buffer_as_commands;
    }
    elsif( $self->{is_framify} ) {
        return $self->make_command_framify;
    }
    elsif( $self->is_textnode ) {
        return $self->make_command_textnode;
    }
    elsif( $self->{cdata} ) {
    	return unless $self->{is_new};
        return $self->make_command_cdata ;
    }
    else {
        return $self->make_command_new, $self->get_buffer_as_commands;
    }
}

##############################################################
sub make_command_new 
{
	my( $self ) = @_;
	return unless $self->{is_new};
    # return unless $self->get_tag;
    
	my @cmd = ( 'new', 
                $self->{orig_id}, 
                $self->get_tag, 
                ( $self->get_parent_id || '' )
              );
	push @cmd, $self->{index} if exists $self->{index};

    delete $self->{orig_id};

    return \@cmd;
}

##############################################################
sub make_command_bye 
{
	my( $self, $parent_id, $index ) = @_;
    return [ bye => $self->{id}] #, $parent_id, $index ];
}

##############################################################
sub make_command_textnode
{
	my( $self ) = @_;
    return unless $self->{buffer} and $self->{buffer}[-1];
    # use Data::Dumper;
    # warn Dumper $self->{buffer};
    my $ret = [ 'textnode',
                $self->get_parent_id, 
                $self->{index},
                $self->{buffer}[-1][-1]
              ];
    return $ret;
}

##############################################################
sub make_command_textnode_bye 
{
	my( $self, $parent_id, $index ) = @_;
    return [ 'bye-textnode', $parent_id, $index ];
}

##############################################################
sub make_command_cdata
{
	my( $self ) = @_;
    # use Data::Dumper;
    # warn Dumper $self->{buffer};
    my $ret = [ 'cdata',
                $self->get_parent_id, 
                $self->{index},
                $self->{cdata}
              ];
    return $ret;
}

##############################################################
sub make_command_cdata_bye 
{
	my( $self, $parent_id, $index ) = @_;
    return [ 'bye-cdata', $parent_id, $index ];
}


##############################################################
sub make_command_SID
{
    my( $package, $SID ) = @_;
    return [ 'SID', $SID ];
}

##############################################################
sub make_command_boot
{
    my( $package, $msg ) = @_;
    return [ 'boot', $msg ];
}

#############################################################
sub make_command_set 
{
	my($self, $key, $value) = @_;

    return [ 'set', $self->get_id, $key, $value ];
}

#############################################################
sub make_command_remove
{
	my($self, $key) = @_;
    return [ 'remove', $self->get_id, $key ];
}

#############################################################
sub make_command_framify
{
	my( $self ) = @_;

    DEBUG and warn "framify is_new=$self->{is_new} is_framify=$self->{is_framify}";

    my @ret = ( $self->make_command_new, $self->get_buffer_as_commands );
    push @ret, [ framify => $self->{id} ] if $self->{is_framify} == 1;
    $self->{is_framify} = 2;
#    use Data::Dumper;
#    warn "framify = ", Dumper \@ret;
    return @ret;
}



#############################################################
sub get_buffer_as_commands 
{
	my( $self ) = @_;
    # use Data::Dumper;
    # warn Dumper $self->{buffer};
	return $self->get_buffer;
}



#############################################################
sub set_attribute 
{ 
    my( $self, $key, $value ) = @_;
    if( $key eq 'id' and ($self->{orig_id}||'' ) eq $value ) {
        return;
    }
    push @{$self->{buffer}}, $self->make_command_set( $key, $value );
    return;
}

#############################################################
sub remove_attribute 
{ 
    my( $self, $key ) = @_;

    push @{$self->{buffer}}, $self->make_command_remove( $key );
    return;
}

#############################################################
sub is_destroyed  
{ 
    my( $self, $parent, $index ) = @_;
    $self->{is_destroyed} = 1;

    my $cmd;
    if( $self->{is_textnode} ) {
        $cmd = $self->make_command_textnode_bye( $parent->id, $index );
    }
    else {
        $cmd = $self->make_command_bye( $parent->id, $index );
    }
    # 2007/05 -- If the node disapears, we want to skip all other commands
    # that might be sent.  However, there might be a case were a commands
    # side effects are desired, so we are pushing.  However that breaks when
    # something is a "late" command.
    push @{ $self->{buffer} }, $cmd;
    return;
}

#############################################################
sub dispose
{
    my( $self ) = @_;
    $self->clear_buffer;
}

# accessors -------------------------------------------------------------------

sub get_id        { $_[0]->{id}           }
sub id            { $_[0]->{id}           }
sub get_tag       { $_[0]->{tag}          }
sub is_new        { $_[0]->{is_new}       }
sub get_buffer    { @{$_[0]->{buffer}}    }
sub is_textnode   { $_[0]->{is_textnode}  }
sub get_parent_id { 
    my( $self ) = @_;
    return unless $self->{parent};
    $self->{parent}->id;
}

# modifiers -------------------------------------------------------------------

sub set_id        { delete $_[0]->{default_id}; $_[0]->{id}           = $_[1]           }
sub set_tag       { $_[0]->{tag}          = lc $_[1]        }
sub set_old       { $_[0]->{is_new}       = 0               }
sub set_index     { $_[0]->{index}        = $_[1]           }
sub clear_buffer  { $_[0]->{buffer}       = []              }
sub set_destroyed { $_[0]->{is_destroyed} = 1               }
sub set_textnode  { $_[0]->{is_textnode} = 1                }
# sub set_parent_id { $_[0]->{parent_id}    = $_[1]           }


1;
