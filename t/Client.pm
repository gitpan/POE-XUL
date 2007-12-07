package t::Client;

use strict;
use warnings;
use Data::Dumper;

use JSON::XS;

our $HAVE_ALGORITHM_DIFF;
BEGIN {
    eval "use Algorithm::Diff";
    $HAVE_ALGORITHM_DIFF = 1 unless $@;
}


use constant DEBUG => 0;
my $NODES = {};

*is = \&main::is;
*ok = \&main::ok;
*isnt = \&main::isnt;
*diag = \&main::diag;
*fail = \&main::fail;
*pass = \&main::pass;


#################################################################
sub new 
{
    my $package = shift;
    my $self = bless { @_ }, $package;
    $self->{APP} ||= 'Test';
    $self->{PORT} ||= 8881;
    $self->{HOST} ||= 'localhost';
    $self->{name} ||= '';
    $self->{NODES} = $NODES;
    $self->{NODES} = {} if $self->{parent};
    return $self;
}


######################################################
sub get_node
{
    my( $self, $id ) = @_;
    return $self->{NODES}->{$id};
}

######################################################
sub decode_resp
{
    my( $self, $resp, $phase ) = @_;
    ok( $resp->is_success, "'$phase' successful" );
    
    is( scalar $resp->content_type, 'application/json', 
            "Right content type" ) or die $resp->content;

    my $content = $resp->content;
    # warn "content='$content'";
    my $data;
    if( $JSON::XS::VERSION > 2 ) {
        $data = JSON::XS::decode_json( $content );
    }
    else {
        $data = JSON::XS::from_json( $content );
    }
    is( ref( $data ), 'ARRAY', "'$phase' returned an array" ) or die Dumper $data;
    return $data;
}

######################################################
sub check_boot
{
    my( $self, $data ) = @_;

    is( $data->[0][0], 'SID', "First response is the SID" );
    is( $data->[1][0], 'boot', "Second response is the boot message" );
    is( $data->[2][0], 'new', "Second response is the new" );
    is( $data->[2][2], 'window', " ... window" );
}

######################################################
sub handle_resp
{
    my( $self, $data, $phase ) = @_;

    local $self->{deleted} = {};
    return unless @$data;

#    warn Dumper $data;
    foreach my $I ( @$data ) {
        my( $op, $id, @args ) = @$I;
        next unless $op;
        if( $op eq 'ERROR' ) {
            die $I->[2];
        }

        next if $id and $self->{deleted}{ $id };
        if( $op eq 'SID' ) {
            ok( !$self->{SID}, "New SID $id" );
            $self->{SID} = $id;
        }
        elsif( $op eq 'boot' ) {
            ok( !$self->{boot}, "Boot message '$id'" );
            $self->{boot} = $id;
        }
        elsif( $op eq 'textnode' ) {
            ok( defined( $args[1] ), "Got a textnode $id" );
            ok( $self->{NODES}->{$id}, " ... and we have its parent ($id)" );
            my $parent = $self->{NODES}->{$id}{zC};
            ok( ( $args[0] <= @{$parent} ), " ... and this isn't way out there" );
            my $tn = $parent->[ $args[0] ];
            if( $tn and $tn->{tag} eq 'textnode' ) {
                $tn->{nodeValue} = $args[1];
            }
            else {
                $parent->[ $args[0] ] =
                    { tag=>'textnode', nodeValue=>$args[1] };
            }
        }
        elsif( $op eq 'cdata' ) {
            ok( defined( $args[1] ), "Got a cdata $id" );
            ok( $self->{NODES}->{$id}, " ... and we have its parent ($id)" );
            my $parent = $self->{NODES}->{$id}{zC};
            ok( ( $args[0] <= @{$parent} ), " ... and this isn't way out there" );
            my $tn = $parent->[ $args[0] ];
            if( $tn and $tn->{tag} eq 'cdata' ) {
                $tn->{nodeValue} = $args[1];
            }
            else {
                $parent->[ $args[0] ] =
                    { tag=>'cdata', cdata=>$args[1] };
            }
        }
        elsif( $op eq 'new' ) {
            ok( ! $self->{NODES}->{$id}, "New node $id" );
            ok( $args[0], " ... with a tag type" );
            my $new = $self->{NODES}->{$id} = 
                        { tag => $args[0], id=>$id, zC=>[] };
            if( $args[1] ) {
                my $parent = $self->{NODES}->{$args[1]};
                ok( $parent, " ... and we have its parent ($args[0] wants $args[1])" );

                my $old = $parent->{zC}[ $args[2] ];
                if( $old ) {
                    delete $self->{NODES}->{ $old->{id} };
                }

                $parent->{zC}[ $args[2] ] = $new
            }
            if( ($new->{tag}||'') eq 'window' ) {
                ok( !$self->{W}, "New window" );
                $self->{W} = $new;
            }
        }
        elsif( $op eq 'set' ) {
            ok( 2==@args, "Going to set attribute $args[0]" );
            my $m = 'an existing node'; 
            $m = $args[1] if $args[0] eq 'id';
            ok( $self->{NODES}->{$id}, " ... on $m" )
                    or die "Where is $id in ", join ', ', sort keys %{ $self->{NODES} }, 
                                    Dumper $I;

            isnt( $self->{NODES}->{$id}{tag}, 'textnode', 
                            "One can't reference a text node!" );

            if( $args[0] eq 'id' ) {
                my $N = delete $self->{NODES}->{$id};
                DEBUG and diag( "$N->{id} -> $args[1]" );
                $N->{id} = $args[1];
                $self->{NODES}->{ $N->{id} } = $N;
            }
            else {
                $self->{NODES}->{$id}{$args[0]} = $args[1];
            }
        }
        elsif( $op eq 'remove' ) {
            ok( 1==@args, "Going to remove attribute $args[0]" );
            ok( $self->{NODES}->{$id}, " ... on an existing node" )
                    or die "Where is $id in ", join ', ', sort keys %{ $self->{NODES} }, 
                                    Dumper $I;

            delete $self->{NODES}->{$id}{$args[0]};
        }
        elsif( $op eq 'bye' ) {
            next unless $self->{NODES}->{$id};

            ok( 0==@args, "Going to delete element $id" );
            ok( $self->{NODES}->{$id}, " ... we know that node" );
            isnt( $self->{NODES}->{$id}{tag}, 'textnode', 
                            " ... can't reference a text node" );
            my $old = delete $self->{NODES}->{$id};

            my( $parent, $index ) = $self->find_parent( $old );

            if( $parent and defined $index ) {
                ok( $parent, " ... and we know the parent" );
                ok( defined $index, " ... we know the offset" );
                my $node = splice @{ $parent->{zC} }, $index, 1;
                is( $old, $node, " ... it's right node" );
            }
            else {
                pass( " ... parent is already bye-bye" );
            }
            $self->drop_node( $old );
        }
        elsif( $op eq 'bye-textnode' ) {
            ok( 1==@args, "Going to delete textnode $args[0] from $id" );
            if( $self->{NODES}->{$id} ) {
                ok( $self->{NODES}->{$id}, " ... we know of the node" );
                ok( ( $args[0] < @{ $self->{NODES}->{$id}{zC} } ), " ... in range" );
                my $node = splice @{ $self->{NODES}->{$id}{zC} }, $args[0], 1;
                is( $node->{tag}, 'textnode', " ... it's a textnode" );
            }
            else {
                pass( " ... already bye-bye" );
            }
        }
        elsif( $op eq 'framify' ) {
            ok( 0==@args, "Going to framify element $id" );
            ok( $self->{NODES}->{$id}, " ... we know of the node" );
            isnt( $self->{NODES}->{$id}{tag}, 'textnode', 
                            " ... can't framify a text node" );
            my $old = delete $self->{NODES}->{$id};

            my( $parent, $index ) = $self->find_parent( $old );

            ok( $parent, " ... and we know the parent of $old->{id}" )
                    or die "We need to know the parent!";
            ok( ( $index < @{ $parent->{zC} } ), " ... in range" );

            my $new = {
                        tag => 'iframe',
                        id  => "IFRAME-$old->{id}",
                        src => { type      => 'XUL-from', 
                                 source_id => $old->{id}
                               }
                    };
            ok( !$self->{NODES}->{$new->{id}}, " ... never been framified" );
            $self->{NODES}->{$new->{id}} = $new;

            my $node = splice @{ $parent->{zC} }, $index, 1, $new;
            is( $old, $node, " ... it's right node" );
            $self->drop_node( $node );
        }
        elsif( $op eq 'popup_window' ) {
            $self->popup_window( $id, @args );
        }
        elsif( $op eq 'close_window' ) {
            $self->close_window( $id, @args );
        }
        elsif( $op eq 'timeslice' ) {
            # ignore it
        }
        else {
             die "What do i do with op=$op";
        }
    }
}

######################################################
sub find_parent
{
    my( $self, $node ) = @_;
    return unless defined $node;
    foreach my $N ( values %{$self->{NODES}} ) {
        next if $N->{tag} eq 'textnode' or $N->{tag} eq 'cdata';
        use Data::Dumper;
        die Dumper $N unless $N->{zC};
        for( my $q1=0; $q1 < @{ $N->{zC} }; $q1++ ) {
            unless( defined $N->{zC}[ $q1 ] ) {
                # die "$q1=", Dumper $N->{zC};
                next;
            }
            next unless $N->{zC}[$q1] == $node;
            return $N, $q1 if wantarray;
            return $N;
        }
    }
    return;
}

######################################################
sub find_ID
{
    my( $self, $id ) = @_;
    return $self->{NODES}->{ $id };
}



############################################################
sub is_visible
{
    my( $self, $node ) = @_;
    $node = $self->find_ID( $node ) unless ref $node;
    return not ( ($node->{style}||'') =~ /display:\s*none/ );
}


######################################################
sub nodeText
{
    my( $self, $node ) = @_;
    return $node->{nodeValue} if $node->{tag} eq 'textnode';
    my @ret;
    foreach my $N ( @{ $node->{zC} } ) {
        push @ret, $self->nodeText( $N );
    }
    return @ret if wantarray;
    return join " ", @ret;
}

######################################################
sub drop_node
{
    my( $self, $node ) = @_;
    if( $node->{id} ) {
        delete $self->{NODES}->{ $node->{id} };
        $self->{deleted}{ $node->{id} } = 1;
    }

    return if not $node->{tag} or $node->{tag} eq 'textnode' or $node->{tag} eq 'cdata';
    foreach my $C ( @{ $node->{zC} } ) {
        $self->drop_node( $C );
    }
    $node->{zC} = [];
}

######################################################
sub root_uri
{
    my( $self ) = @_;
    return URI->new( "http://$self->{HOST}:$self->{PORT}/" );
}

######################################################
sub base_uri
{
    my( $self ) = @_;
    return URI->new( "http://$self->{HOST}:$self->{PORT}/xul" );
}

######################################################
sub boot_uri
{
    my( $self ) = @_;
    my $URI = $self->base_uri;
    $URI->query_form( $self->boot_args );
    return $URI;
}

######################################################
sub boot_args
{
    my( $self, $button ) = @_;
    return { app=> $self->{APP} };
}

######################################################
sub Click
{
    my( $self, $button ) = @_;

    $button = $self->find_ID( $button ) unless ref $button;
    ok( $button, "Found button" )
            or die "I really need that button";

    my $URI = $self->Click_uri( $button );
    my $resp = $self->{UA}->get( $URI );
    my $data = $self->decode_resp( $resp, "Click $button->{id}" );
    die Dumper $data if $data->[0][0] eq 'ERROR';
    $self->handle_resp( $data, "Click $button->{id}" );
}

######################################################
sub Click_uri
{
    my( $self, $button ) = @_;
    ok( $button->{id}, "Clicking on $button->{id}" );
    my $URI = $self->base_uri;
    $URI->query_form( $self->Click_args( $button ) );
    return $URI;
}

######################################################
sub Click_args
{
    my( $self, $button ) = @_;
    return {    app => $self->{APP}, 
                SID => $self->{SID}, 
                event => 'Click', 
                source_id => $button->{id}
            };
}

######################################################
sub Change
{
    my( $self, $node, $value ) = @_;
    $node = $self->find_ID( $node ) unless ref $node;
    ok( $node, "Found $node->{id}" ) or die "I really need that node";

    $node->{value} = $value;

    my $URI = $self->Change_uri( $node );
    my $resp = $self->{UA}->get( $URI );
    my $data = $self->decode_resp( $resp, "Change $node->{id}" );
    die Dumper $data if $data->[0][0] eq 'ERROR';
    $self->handle_resp( $data, "Change $node->{id}" );    
}

######################################################
sub Change_uri
{
    my( $self, $textbox ) = @_;
    ok( $textbox->{id}, "Changing on $textbox->{id}" );
    my $URI = $self->base_uri;
    $URI->query_form( $self->Change_args( $textbox ) );
    return $URI;
}

######################################################
sub Change_args
{
    my( $self, $textbox ) = @_;
    return {    app => $self->{APP}, 
                SID => $self->{SID}, 
                event => 'Change', 
                source_id => $textbox->{id},
                value => $textbox->{value}
            };
}

######################################################
sub Select_args
{
    my( $self, $textbox ) = @_;
    return {    app => $self->{APP}, 
                SID => $self->{SID}, 
                event => 'Select', 
                source_id => $textbox->{id},
                selectedIndex => $textbox->{selectedIndex}
            };
}

######################################################
sub RadioClick_args
{
    my( $self, $RG, $index ) = @_;

    ok( $RG, "Going to click a radio" );

    my $selectedId;
    if( ref $index ) {
        $selectedId = $index->{id};
    }
    else {
        my $radio = $RG->{zC}[ $index ];
        ok( $radio, " ... got the radio" );
        is( $radio->{tag}, 'radio', " ... yep, it's a radio" );
        $selectedId = $radio->{id};
    }


    return {    app => $self->{APP}, 
                SID => $self->{SID}, 
                event => 'RadioClick', 
                source_id => $RG->{id},
                selectedId => $selectedId
            };
}

############################################################
sub Connect
{
    my( $self ) = @_;
    my $URI = $self->Connect_uri;
    my $resp = $self->{UA}->get( $URI );
    my $data = $self->decode_resp( $resp, "Connect $self->{name}" );
    die Dumper $data if $data->[0][0] eq 'ERROR';
    $self->handle_resp( $data, "Connect $self->{name}" );    
}

sub Connect_uri
{
    my( $self ) = @_;

    my $URI = $self->base_uri;
    $URI->query_form( $self->Connect_args );
    return $URI;
}

sub Connect_args
{
    my( $self ) = @_;
    return { app => $self->{APP}, 
             SID => $self->{SID},
             event  => 'connect',
             window => $self->{name}
           };
}

######################################################
sub Disconnect
{
    my( $self, $win ) = @_;
    my $URI = $self->Disconnect_uri( $win );
    my $resp = $self->{UA}->get( $URI );
    my $data = $self->decode_resp( $resp, "Disconnect $win->{id}" );
#    is( 0+@$data, 0, "No response to Disconnect" );
#    return;
    $self->handle_resp( $data, "Disconnect $win->{id}" );    
}

sub Disconnect_uri
{
    my( $self, $win ) = @_;

    my $URI = $self->base_uri;
    $URI->query_form( $self->Disconnect_args( $win ) );
    return $URI;
}

sub Disconnect_args
{
    my( $self, $win ) = @_;
    return { app => $self->{APP}, 
             SID => $self->{SID},
             event  => 'disconnect',
             window => $win->{id},
#             value  => $win->{id}
           };
}



######################################################
sub XULFrom_args
{
    my( $self, $ID ) = @_;
    return {    app => $self->{APP}, 
                SID => $self->{SID}, 
                event => 'XUL-from', 
                source_id => $ID
            };
}

######################################################
sub SearchList_args
{
    my( $self, $SL, $string ) = @_;

    ok( $SL, "Going to search a search-list" );
    ok( $string, " ... for '$string'" );

    return {    app => $self->{APP}, 
                SID => $self->{SID}, 
                event => 'SearchList', 
                source_id => $SL->{id},
                value => $string
            };
}

############################################################
sub server_size
{
    my( $self, $UA ) = @_;
    my $SIZEuri = $self->base_uri;
    $SIZEuri->path( '/__poe_size' );

    my $resp = $UA->get( $SIZEuri );
    ok( $resp->is_success, "Got the kernel size" );
    is( $resp->content_type, 'text/plain', " ... as text/plain" );

    my $size = 0+$resp->content;
    ok( $size, " ... and it is non-null" );
    return $size;
}

############################################################
sub server_dump
{
    my( $self, $UA ) = @_;
    my $URI = $self->base_uri;
    $URI->path( '/__poe_kernel' );

    my $resp = $UA->get( $URI );
    ok( $resp->is_success, "Got the kernel dump" );
    is( $resp->content_type, 'text/plain', " ... as text/plain" );

    return $resp->content;
}

############################################################
sub compare_dumps
{
    my( $self, $DUMP1, $DUMP2 ) = @_;
    return unless $HAVE_ALGORITHM_DIFF;

    my $diff = Algorithm::Diff->new( [ split "\n", $DUMP1 ],
                                     [ split "\n", $DUMP2 ] );
    $diff->Base( 1 );   # Return line numbers, not indices
    while(  $diff->Next()  ) {
        next   if  $diff->Same();
        my $sep = '';
        if(  ! $diff->Items(2)  ) {
            printf "%d,%dd%d\n",
               $diff->Get(qw( Min1 Max1 Max2 ));
        } elsif(  ! $diff->Items(1)  ) {
            printf "%da%d,%d\n",
               $diff->Get(qw( Max1 Min2 Max2 ));
        } else {
            $sep = "---\n";
            printf "%d,%dc%d,%d\n",
               $diff->Get(qw( Min1 Max1 Min2 Max2 ));
        }
        print "- $_\n"   for  $diff->Items(1);
        # print $sep;
        print "+ $_\n"   for  $diff->Items(2);
    }
}

############################################################
sub popup_window
{
    my( $self, $id, @args ) = @_;
    
    ok( !$self->{windows}{$id}, "Popup window $id" )
            or die "Pain follows";

    push @{ $self->{new_windows} }, $id;
    $self->{windows}{ $id } = { id => $id };
}


############################################################
sub close_window
{
    my( $self, $id, @args ) = @_;
    if( $self->{parent} ) {
        return $self->{parent}->close_window( $id, @args );
    }

    my $win = delete $self->{windows}{$id};
    ok( $win, "Close window $id" )
            or die "Pain follows";

    $self->Disconnect( $win );
}

############################################################
sub open_window
{
    my( $self ) = @_;
    my $win_id = pop @{ $self->{new_windows} };
    my $win2 = ref( $self )->new( parent => $self, name => $win_id );

    my @copy = qw( HOST PORT UA APP SID );
    @{ $win2 }{ @copy } = @{ $self }{ @copy };

    $self->{windows}{ $win_id }{browser} = $win2;

    return $win2;
}

1;
