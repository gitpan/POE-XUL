package t::Server;

use strict;
use Config;

our $perl;

BEGIN {
    *DEBUG = \&main::DEBUG;
    $perl = $^X || $Config{perl5} || $Config{perlpath};

    if( $ENV{HARNESS_PERL_SWITCHES} ) {
        $perl .= " $ENV{HARNESS_PERL_SWITCHES}";
    }
}

sub spawn
{
    my( $package, $port, $root, $prog ) = @_;
    my $pid = fork;
    die "Unable to fork" unless defined $pid;
    return $pid if $pid;
    $root ||= 'poe-xul';
    $prog ||= 't/test-app.pl';
#    warn( "# $perl -Iblib/lib -I../widgets/blib/lib -I../httpd/blib/lib -I../PRO5/blib/lib $prog $port $root\n" );
    exec( "$perl -Iblib/lib -I../widgets/blib/lib -I../httpd/blib/lib -I../PRO5/blib/lib $prog $port $root" ) or die $!;
}

1;
