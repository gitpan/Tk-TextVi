#
# Informational commands
#
# ga
#

use strict;
use warnings;

use Tk;
use Tk::TextVi;
use Test::Simple tests => 1;

my $mw = new MainWindow;
my $t = $mw->TextVi();

$t->Contents( <<END );
Testing Tk::TextVi
Some lines of sample text
With a blank line:

Which has some special cases
0123456789
END

$t->SetCursor( '5.8' );
$t->InsertKeypress( 'g' );
$t->InsertKeypress( 'a' );

ok( $t->viMessage eq '<s>  115,  Hex 73,  Oct 163', 's' );

