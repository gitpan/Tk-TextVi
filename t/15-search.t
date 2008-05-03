#
# Search commands
#
# n
# /
#

use strict;
use warnings;

use Tk;
use Tk::TextVi;
use Test::Simple tests => 7;

my $mw = new MainWindow;
my $t = $mw->TextVi();

$t->Contents( <<END );
Testing Tk::TextVi
Some lines of sample Text
With a blank line:

Which has some special cases
0123456789
END

sub test {
    my ($cmds) = @_;
    $t->InsertKeypress( $_ ) for split //, $cmds;
}

# /

$t->SetCursor( '1.0' );

test( '/T' );
ok( $t->index('insert') eq '1.0', "Pattern matches at cursor" );

test( 'ex' );
ok( $t->index('insert') eq '1.12', "Add to pattern" );

test( "\b" );
ok( $t->index('insert') eq '1.0', "Delete from pattern" );

test( "(" );
ok( $t->index('insert') eq '1.0', "Incomplete pattern" );

test( "\bx\c[" );
ok( $t->index('insert') eq '1.0', "Escape cancels" );

test( "/Tex\n" );
ok( $t->index('insert') eq '1.12', "Enter confirms" );

# n

test( "n" );
ok( $t->index('insert') eq '2.21', "n finds the next match" );

