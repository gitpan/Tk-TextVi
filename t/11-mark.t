# 
# Tests the mark-based motion commands
#
# m
# `
#

use strict;
use warnings;

use Tk;
use Tk::TextVi;
use Test::Simple tests => 2;

my $mw = new MainWindow;

my $t = $mw->TextVi();

$t->Contents( <<END );
Testing Tk::TextVi
Some lines of sample text
With a blank line:

Which has some special cases
0123456789
END

sub test {
    my ($init, $cmds) = @_;
    $t->SetCursor( $init );
    $t->InsertKeypress( $_ ) for split //, $cmds;
}

test( '1.5', 'ma' );
test( '1.0', '`a' );
ok( $t->index('insert') eq '1.5', 'Set and jumped to mark' );

test( '2.5', 'ma' );
test( '6.9', '`a' );
ok( $t->index('insert') eq '2.5', 'Reset and jumped to mark' );