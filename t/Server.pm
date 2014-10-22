package t::Server;

use strict;
use Config;
use POE;

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
    warn "POE is in $INC{'POE.pm'}";
    warn "perl=$perl";
    my $inc = join ' ', map { "-I$_" } qw( blib/lib
                                           ../widgets/blib/lib
                                           ../httpd/blib/lib
                                            ../PRO5/blib/lib
                                          ), @INC;
    exec( "$perl $inc $prog $port $root" ) or die $!;
}

1;
