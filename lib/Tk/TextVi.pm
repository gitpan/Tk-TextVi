package Tk::TextVi;

use strict;
use warnings;

our $VERSION = '0.01';

#use Data::Dump qw|dump|;

use Tk;
use Tk::TextUndo ();
use base qw'Tk::Derived Tk::TextUndo';

use Carp qw'carp croak';

Construct Tk::Widget 'TextVi';

# Constants for keys that Tk treats special
sub BKSP () { "\cH" }
sub TAB  () { "\cI" }
sub ESC  () { "\c[" }

# Constants used for exceptions
sub X_NO_KEYS   () { "VI_NO_KEYS\n" }
sub X_BAD_STATE () { "VI_BAD_STATE\n" }
sub X_NO_MOTION () { "VI_NO_MOTION\n" }

# Constants used for flags
sub F_STAT () { 1 }
sub F_MSG () { 2 }
sub F_ERR () { 4 }

# Default command mappings and what file holds their test data
my %map = (
    n => {
        a => \&vi_n_a,                              # 30-insert
        d => \&vi_n_d,                              # 20-delete
        f => \&vi_n_f,                              # 13-findchar
        g => {
            a => \&vi_n_ga,                         # 60-info
            g => \&vi_n_gg,                         # 10-move
        },
        h => \&vi_n_h,                              # 10-move
        i => \&vi_n_i,                              # 30-insert
        j => \&vi_n_j,                              # 10-move
        k => \&vi_n_k,                              # 10-move
        l => \&vi_n_l,                              # 10-move
        m => \&vi_n_m,                              # 11-mark
        n => \&vi_n_n,                              # 15-search
        o => \&vi_n_o,                              # 30-insert
        p => \&vi_n_p,                              # 40-register
        q => \&vi_n_q,                              # 41-macro
        r => \&vi_n_r,                              # 21-replace
        t => \&vi_n_t,                              # 13-findchar
        u => \&vi_n_u,
        v => \&vi_n_v,
        x => \'dl',                                 # 20-delete
        y => \&vi_n_y,                              # 40-register

        D => \'d$',                                 # 20-delete
        G => \&vi_n_G,                              # 10-move
        O => \&vi_n_O,                              # 30-insert
        V => \&vi_n_V,

        0 => [ 'insert linestart', 'char', 'inc' ], # 10-move

        '`' => \&vi_n_backtick,                     # 11-mark
        '@' => \&vi_n_at,                           # 41-macro
        '$' => \&vi_n_dollar,                       # 10-move
        '%' => \&vi_n_percent,                      # 14-findline
        ':' => \&vi_n_colon,
        '/' => \&vi_n_fslash,                       # 15-search
    },
    c => {
        q => \&vi_c_quit,
        quit => \&vi_c_quit,
        map => \&vi_c_map,
        noh => \&vi_c_nohlsearch,
        nohl => \&vi_c_nohlsearch,
        nohlsearch => \&vi_c_nohlsearch,
        split => \&vi_c_split,
    },
    v => {
        d => \&vi_n_d,
        f => \&vi_n_f,
        g => {
            g => [ '1.0', 'line', 'inc' ],
        },
        h => \&vi_n_h,
        j => \&vi_n_j,
        k => \&vi_n_k,
        l => \&vi_n_l,
        t => \&vi_n_t,

        G => \&vi_n_G,

        0 => [ 'insert linestart', 'char', 'inc' ],
        '`' => \&vi_n_backtick,
        '$' => \&vi_n_dollar,
        '%' => \&vi_n_percent,
        '"' => \&vi_n_quote,
    }
);

# Tk derived class initializer
sub ClassInit {
    my( $self, $mw ) = @_;

    $self->SUPER::ClassInit( $mw );

    # TODO: Kill default Tk::Text Bindings

    # Convert keys that Tk handles specially into normal keys
    # TODO: Add missing keys
    $mw->bind( $self, '<BackSpace>',    [ 'InsertKeypress', BKSP ] );
    $mw->bind( $self, '<Tab>',          [ 'InsertKeypress', TAB ] );
    $mw->bind( $self, '<Escape>',       [ 'InsertKeypress', ESC ] );
    $mw->bind( $self, '<Return>',       [ 'InsertKeypress', "\n" ] );

    return $self;
}

# Constructor
sub Populate {
    my ($w,$args) = @_;

    $w->SUPER::Populate( $args );

    $w->{VI_PENDING} = '';      # Pending command
    $w->{VI_MODE} = 'n';        # Start in normal mode
    $w->{VI_REGISTER} = { };    # Empty registers
    $w->{VI_SETTING} = { };     # No settings
    $w->{VI_ERROR} = [ ];       # Pending errors
    $w->{VI_MESSAGE} = [ ];     # Pending messages
    $w->{VI_FLAGS} = 0;         # Pending flags

    # XXX: There might be a legit reason in the future to have two
    # Tk::TextVi widgets with different mappings.
    $w->{VI_MAPS} = \%map;   # Command mapping

    $w->tagConfigure( 'VI_SEARCH', -background => '#FFFF00' );

    $w->ConfigSpecs(
        -statuscommand  =>  [ 'CALLBACK', 'statusCommand', 'StatusCommand', 'NoOp' ],
        -messagecommand => ['CALLBACK', 'messageCommand', 'MessageCommand', 'NoOp' ],
        -errorcommand => [ 'CALLBACK', 'errorCommand', 'ErrorCommand', 'NoOp' ],
        -systemcommand => ['CALLBACK', 'systemCommand', 'SystemCommand', 'NoOp' ],
    );
}

# We don't want to lose the selection.
# Movement commands extend visual selection
sub SetCursor {
    my($w,$pos) = @_;
    $pos = 'end -1c' if $w->compare($pos,'==','end');
    $w->markSet('insert',$pos);
    $w->see('insert');

    if( $w->{VI_MODE} eq 'v' ) {
        $w->tagRemove( 'sel', '1.0', 'end' );
        
        my ($s,$e) = ($w->{VI_VISUAL_START}, 'insert');
        if( $w->compare( $e, '<', $s ) ) {
            $w->tagAdd( 'sel', $e, $s );
        }
        else {
            $w->tagAdd( 'sel', $s, $e );
        }
    }
    elsif( $w->{VI_MODE} eq 'V' ) {
        $w->tagRemove( 'sel', '1.0', 'end' );
        
        my ($s,$e) = ($w->{VI_VISUAL_START}, 'insert');
        if( $w->compare( $e, '<', $s ) ) {
            $w->tagAdd( 'sel', "$e linestart", "$s lineend" );
        }
        else {
            $w->tagAdd( 'sel', "$s linestart", "$e lineend" );
        }
    }
}

# Deep Experimental Magic
# 
# Only invoke the special split-variant functions when we're using
# :split
my @split_func = qw| delete insert tagAdd tagConfigure tagRemove |;

{
    no strict;
    for my $func ( @split_func ) {
        *{ "split_$func" } = sub {
            my ($w,@args) = @_;

            if( defined $w->{VI_SPLIT_SHARE} ) {
                for my $win ( @{ $w->{VI_SPLIT_SHARE} } ) {
                    "Tk::TextUndo::$func"->( $win, @args );
                }
            }
            else {
                "Tk::TextUndo::$func"->( $w, @args );
            }
        }
    }
}

sub vi_split {
    my ($w,$newwin) = @_;

    # First time replace all the functions with the magical split versions
    if( not defined $w->{VI_SPLIT_SHARE} ) {
        $w->{VI_SPLIT_SHARE} = [ $w ];

        no strict;
        for my $func (@split_func) {
            *{"Tk::TextVi::$func"} = \&{"split_$func"};
        }
    }

    $newwin->Contents( $w->Contents );
    $newwin->SetCursor( $w->index('insert') );
    $newwin->yviewMoveto( ($w->yview)[0] );

    push @{$w->{VI_SPLIT_SHARE}}, $newwin;
    $newwin->{VI_SPLIT_SHARE} = $w->{VI_SPLIT_SHARE}
}

# Public Methods #####################################################

sub viMode {
    my ($w, $mode) = @_;
    my $rv = $w->{VI_MODE};
    $rv .= 'q' if defined $w->{VI_RECORD_REGISTER};

    if( defined $mode ) {
        croak "Tk::TextVi received invalid mode '$mode'"
            if $mode !~ m[ ^ [nicvV/] $ ]x;
        $w->{VI_MODE} = $mode;
        $w->{VI_PENDING} = '';

        # XXX: Hack
        if( (caller)[0] eq 'Tk::TextVi' ) {
            $w->{VI_FLAGS} |= F_STAT;
        }
        else {
            $w->Callback( '-statuscommand', $w->{VI_MODE}, $w->{VI_PENDING} );
        }
    }

    return $rv;
}

sub viPending {
    my ($w) = @_;
    return $w->{VI_PENDING};
}

sub viError {
    my ($w) = @_;
    return shift @{ $w->{VI_ERROR} };
}

sub viMessage {
    my ($w) = @_;
    return shift @{ $w->{VI_MESSAGE} };
}

sub viMap {
    my ( $w, $mode, $sequence, $ref, $force ) = @_;

    # TODO: nmap,imap,vmap etc. support
    my @mapmodes = map { $w->{MAPS}{$_} } split //, $mode;

    while( length( $sequence ) > 1 ) {
        # Get the next character in the sequence
        my $c = substr $sequence, 0, 1, '';

        # Advance the mapping locations
        for my $map ( @mapmodes ) {

            # Nothing at this location yet, add a hash
            if( not defined $map->{$c} ) {
                $map->{$c} = { };
            }
            # Something is already mapped here
            elsif( 'HASH' ne ref $map->{$c} ) {
                return unless $force;
                # If $force was defined, nuke the previous entry
                $map->{$c} = { };
            }

            $map = $map->{$c};
        }
    }

    # Check that a mapping can be placed here
    for my $map ( @mapmodes ) {
        if( defined $map->{$sequence} and       # Something is here
            'HASH' eq ref $map->{$sequence} and # it's a longer mapping
            scalar keys %{ $map->{$sequence}} ) # and its in use
        {
            return unless $force;
            delete $map->{$sequence};           # wipe out existing maps
        }
    }

    for my $map ( @mapmodes ) {
        $map->{$sequence} = $ref;
    }

    # TODO: return the mappings that were replaced in a format that
    # would permit them to be restored
    return 1;
}

# 'Private' Methods ##################################################

# Store text in a register
#
# Caller is responsible for determining when text should also be
# written to the unnamed register or the small delete register at the
# moment (XXX: This should be handled here in the future)
sub registerStore {
    my ( $w, $register, $text ) = @_;

    # Registers are all single characters or unnamed
    die X_BAD_STATE if length($register) > 1;

    # Read-only registers and blackhole are never written to
    return if $register =~ /[_:.%#]/;

    # Always store in the unnamed register
    $w->{VI_REGISTER}{''} = $text;

    # * is the clipboard
    if( $register eq '*' ) {
        $w->clipboardClear;
        $w->clipboardAppend( '--', $text );
    }
    else {
        $w->{VI_REGISTER}{$register} = $text;
    }
}

# Fetch the contents of a register
sub registerGet {
    my ( $w, $register ) = @_;

    # Registers are single characters or unnamed
    die X_BAD_STATE if length($register) > 1;

    # Nothing comes out of a black hole
    return '' if $register eq '_';

    # TODO: other special registers

    # Register contains nothing
    return '' unless defined $w->{VI_REGISTER}{$register};

    return $w->{VI_REGISTER}{$register};
}

sub setMessage {
    my ($w,$msg) = @_;

    push @{ $w->{VI_MESSAGE} }, $msg;
    $w->{VI_FLAGS} |= F_MSG;
}

sub setError {
    my ($w,$msg) = @_;

    push @{ $w->{VI_ERROR} }, $msg;
    $w->{VI_FLAGS} |= F_ERR;
}

# Handle keyboard input
#
# Replaces method in Tk::Text
sub InsertKeypress {
    my ($w,$key) = @_;
    my $res;

    return if $key eq '';       # Ignore shift, control, etc.

    $w->{VI_RECORD_KEYS} .= $key if defined $w->{VI_RECORD_REGISTER};

    # Normal mode
    if( $w->{VI_MODE} eq 'n' ) {
        # Escape cancels any command in progress
        if( $key eq ESC ) {
            $w->viMode('n');
        }
        else {
            $res = $w->InsertKeypressNormal( $key );

            # Array ref is returned by motion commands
            if( 'ARRAY' eq ref $res ) {
                $w->SetCursor( $res->[0] );
            }
        }
    }
    # Visual character mode
    elsif( $w->{VI_MODE} eq 'v' ) {
        if( $key eq ESC ) {
            $w->tagRemove( 'sel', '1.0', 'end' );
            $w->viMode('n');
        }
        else {
            $res = $w->InsertKeypressNormal( $key );

            if( 'ARRAY' eq ref $res ) {
                $w->SetCursor( $res->[0] );
            }
        }
    }
    # Visual line mode
    elsif( $w->{VI_MODE} eq 'V' ) {
        if( $key eq ESC ) {
            $w->tagRemove( 'sel', '1.0', 'end' );
            $w->viMode('n');
        }
        else {
            $res = $w->InsertKeypressNormal( $key );

            if( 'ARRAY' eq ref $res ) {
                $w->SetCursor( $res->[0] );
            }
        }
    }
    # Command mode
    elsif( $w->{VI_MODE} eq 'c' ) {
        if( $key eq BKSP ) {
            if( $w->{VI_PENDING} eq '' ) {
                $w->viMode('n');
            }
            else {
                chop $w->{VI_PENDING};
            }
        }
        elsif( $key eq "\n" ) {
            $w->EvalCommand();
            $w->viMode('n');
        }
        elsif( $key eq ESC ) {
            $w->viMode('n');
        }
        else {
            $w->{VI_PENDING} .= $key;
        }
        $w->{VI_FLAGS} |= F_STAT;
    }
    # Incremental search mode
    elsif( $w->{VI_MODE} eq '/' ) {
        if( $key eq BKSP ) {
            if( $w->{VI_PENDING} eq '' ) {
                $w->viMode('n');
            }
            else {
                chop $w->{VI_PENDING};
            }
        }
        elsif( $key eq "\n" ) {
            $w->vi_fslash_end;
            $w->viMode('n');
            return;
        }
        elsif( $key eq ESC ) {
            $w->viMode('n');
        }
        else {
            $w->{VI_PENDING} .= $key;
        }
        $w->SetCursor( $w->vi_fslash() );
        $w->{VI_KEYS} |= F_STAT;
    }
    # Insert mode
    elsif( $w->{VI_MODE} eq 'i' ) {
        if( $key eq ESC ) {
            $w->viMode('n');
            $w->SetCursor( 'insert -1c' )
                if( $w->compare( 'insert', '!=', 'insert linestart' ) );
        }
        elsif( $key eq BKSP ) {
            $w->delete( "insert -1c" );
        }
        else {
            $w->insert( 'insert', $key );
        }
    }
    else {
        die "Tk::TextVi internal state corrupted";
    }

    # Does the UI need to update?
    # XXX: HACK
    if( (caller)[0] ne 'Tk::TextVi' ) {
        $w->Callback( '-statuscommand',
            $w->{VI_MODE} . (defined $w->{VI_RECORD_REGISTER} ? 'q' : ''),
            $w->{VI_PENDING} ) if( $w->{VI_FLAGS} & F_STAT );
        $w->Callback( '-messagecommand' ) if $w->{VI_FLAGS} & F_MSG ;
        $w->Callback( '-errorcommand' ) if $w->{VI_FLAGS} & F_ERR ;

        $w->{VI_FLAGS} = 0;
    }
}

# Handles the command processing shared between Normal
# and visual mode commands
sub InsertKeypressNormal {
    my ($w,$key) = @_;
    my $res;

    $w->{VI_PENDING} .= $key;       # add to pending key strokes
    eval { $res = $w->EvalKeys(); };# try to process as a command

    if( $@ ) {
        die if $@ !~ /^VI_/;        # wasn't our exception

        if( $@ eq X_BAD_STATE ) {   # panic, restore known state
            $w->{VI_PENDING} = '';
        }
    }
    else {                          # The command completed
        $w->{VI_PENDING} = '';
    }

    $w->{VI_FLAGS} |= F_STAT;
    return $res;
}

# Takes a string of keypresses and dispatches it to the right command
sub EvalKeys {
    my ($w, $keys, $count, $register, $motion) = @_;
    my $res;
    my $mode = lc substr $w->{VI_MODE}, 0, 1;       # V and v use the same maps

    $count = 0 unless defined $count;

    # Use the currently pending keys by default
    $keys = $w->{VI_PENDING} unless defined $keys;

    # Extract the count
    if( $keys =~ s/^([1-9]\d*)// ) {
        $count ||= 1;
        $count *= $1;
    }

    # Extract the register
    if( $keys =~ s/^"(.?)// ) {
        $register = $1;
    }

    die X_NO_KEYS if $keys eq '';   # No command here

    # What does this map too
    $res = $w->{VI_MAPS}{$mode}{substr $keys, 0, 1, ''};

    # a hash ref is a multichar mapping, go deeper
    while( 'HASH' eq ref $res ) {
        die X_NO_KEYS if $keys eq '';
        $res = $res->{substr $keys, 0, 1, ''};
    }

    # If left with a function, call it
    $res = $res->( $w, $keys, $count, $register, $motion )
        if 'CODE' eq ref $res;

    # A stringy return means to use these keypresses instead
    if( defined $res and 'SCALAR' eq ref $res ) {
        $w->{VI_PENDING} = '';
        
        for my $key ( split //, $$res . $keys ) {
            $w->InsertKeypress( $key );
        }

        # The above call took care of everything
        die X_NO_KEYS;
    }

    die X_BAD_STATE if $motion and 'ARRAY' ne ref $res;

    return $res;
}

sub EvalCommand {
    my ($w) = @_;

    my ($cmd,$force,$arg);

    if( not $w->{VI_PENDING} =~ /
        ^           # colon is not in the buffer
        (\S+)       # followed by the name of the command
        (!?)        # optional ! to force the command
        (?:
            \s+     # space between command and argument
            (.*)    # everything else is the argument
        )?          # argument is optional
        $/x )
    {
       return;      # Something's really screwed up 
    }

    $cmd = $1;
    $force = 1 if $2;
    $arg = $3;

    return unless exists $w->{VI_MAPS}{c}{$cmd};

    $w->{VI_MAPS}{c}{$cmd}( $w, $force, $arg );
}

# All the normal-mode commands ######################################

=begin comment

sub vi_n_d {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;
}

=cut

sub vi_n_a {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;

    $w->SetCursor( 'insert +1c' )
        unless $w->compare( 'insert', '==', 'insert lineend' );
    $w->viMode('i');
}

sub vi_n_d {
    my ($w,$k,$n,$r,$m) = @_;
    my ($start,$end,$wise,$type);
    die X_BAD_STATE if $m;

    # In a visual mode we just need the selection
    if( $w->{VI_MODE} eq 'v' ) {
        $start = 'sel.first';
        $end = 'sel.last';
        $wise = 'char';
        $type = 'exc';
    }
    elsif( $w->{VI_MODE} eq 'V' ) {
        $start = 'sel.first';
        $end = 'sel.last';
        $wise = 'line';
    }
    # In normal mode there's more work
    else {
        # Special case, dd = delete line
        if( $k eq 'd' ) {
            # If not enough lines, don't delete anything
            return if $n > int $w->index('end') - int $w->index('insert');

            $start = 'insert';
            $end = 'insert';
            $end .= '+' . ($n-1) . 'l' if $n > 1;
            $wise = 'line';
        }
        else {
            my $res = EvalKeys( @_[0 .. 3], 1 );

            $start = 'insert';
            ($end,$wise,$type) = @$res;
        }
    }

    # Swap start and end if the motion was backwards
    if( $w->compare( $start, '>', $end ) ) {
        ($start,$end) = ($end,$start);
        $type = 'exc';                      # XXX: hack
    }

    if( $wise eq 'line' ) {

        $start .= ' linestart';     # From start of line
        $end .= ' lineend +1c';     # Including the \n of the final line
    }
    else {
        $end .= ' +1c' if $type eq 'inc';
    }

    my $text = $w->get( $start, $end );
    $w->delete( $start, $end );

    if( not defined $r ) {
        # With default register, d shifts
        # XXX: can you not get a hash slice with references?
        for my $idx ( 2 .. 9 ) {
            $w->{VI_REGISTER}{ $idx } = $w->{VI_REGISTER}{ $idx-1 };
        }

        # Stores in "1 by default
        $r = '1';

        # If under 1 line, store in small delete register too
        $w->registerStore( '-', $text ) if $text !~ /\n/;
    }

    $w->registerStore( $r, $text );
}

sub vi_n_f {
    my ($w,$k,$n,$r,$m) = @_;

    die X_NO_KEYS if $k eq '';

    my $line = $w->get( 'insert', 'insert lineend' );
    my $ofst = index $line, $k, 1;
    for (2 .. $n) {
        return if $ofst == -1;
        $ofst = index $line, $k, $ofst+1;
    }

    return if $ofst == -1;
    return [ "insert +$ofst c", 'char', 'inc' ];
}

sub vi_n_ga {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;

    my $c = $w->get( 'insert' );

    $w->setMessage(sprintf '<%s>  %d,  Hex %2x,  Oct %03o', $c, (ord($c)) x 3 );
}

sub vi_n_gg {
    my ($w,$k,$n,$r,$m) = @_;

    return [ "$n.0", 'line' ];
}

sub vi_n_h {
    my ($w,$k,$n,$r,$m) = @_;
    $n ||= 1;

    my $ind = ( split /\./, $w->index('insert') )[1];
    return [ 'insert linestart', 'char', 'exc' ] if $ind <= $n;
    return [ "insert -$n c", 'char', 'exc' ];
}

sub vi_n_i {
    my ($w,$k,$n,$r,$m) = @_;
    $w->viMode('i');
}

sub vi_n_j {
    my ($w,$k,$n,$r,$m) = @_;
    $n ||= 1;
    
    # Screwy, Setcursor('end') doesn't make index('insert') == index('end')??
    my $max = int $w->index('end') - 1 - int $w->index('insert');
    $n = $max if $n > $max;

    return if $n == 0;
    [ "insert +$n l", 'line', 'inc' ];
}

sub vi_n_k {
    my ($w,$k,$n,$r,$m) = @_;
    $n ||= 1;

    my $max = int $w->index('insert') - 1;
    $n = $max if $n > $max;

    return if $n == 0;
    [ "insert -$n l", 'line', 'inc' ];
}

sub vi_n_l {
    my ($w,$k,$n,$r,$m) = @_;

    $n ||= 1;
    my $ln = $w->index('insert lineend');
    my $ln_1 = $w->index('insert lineend -1c');
    my $eol = (split /\./, $ln_1)[1];
    my $ins = $w->index('insert');
    my $at = (split /\./, $ins)[1];

    # If the cursor is at TK's end of line or VI end of line, leave it alone
    return ['insert','char','exc'] if $ln eq $ins or $ln_1 eq $ins;
    # If the count would go past lineend - 1, stop at lineend - 1
    return ['insert lineend -1c','char','inc'] if $n + $at >= $eol;
    # Otherwise advance n characters
    return ["insert +$n c",'char','exc'];
}

sub vi_n_m {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;
    die X_NO_KEYS if $k eq '';

    $w->markSet( "VI_MARK_$k", 'insert' );
}

sub vi_n_n {
    my ($w,$k,$n,$r,$m) = @_;
    
    my $re = $w->{VI_SEARCH_LAST};

    if( not defined $re ) {
        $w->setError('No pattern');
        die X_BAD_STATE;
    }

    my $text = $w->get( 'insert +1c', 'end' );

    if( $text =~ $re ) {
        return [ "insert +1c +$-[0]c", 'char', 'exc' ];
    }
}

sub vi_n_o {
    my ($w,$k,$n,$r,$m) = @_;
    die X_NO_MOTION if $m;

    # Work around for some weird behavior in Tk::TextUndo
    # If I just open the line and advance the cursor, I lose
    # test case 6
    my ($l) = 1 + int $w->index('insert');
    $w->insert('insert lineend',"\n");
    $w->SetCursor("$l.0");
    $w->viMode('i');
}

sub vi_n_p {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;

    $r = "" if not defined $r;
    $n ||= 1;

    my $txt = $w->registerGet($r);

    if( index( $txt, "\n" ) == -1 ) {
        # Charwise insert
        $w->insert( 'insert +1c', $txt x $n );
        $n *= length($txt);
        $n += 1;
        $w->SetCursor( "insert +$n c" );
    }
    else {
        # Linewise insert
        $w->insert( 'insert +1l linestart', $txt x $n );
        $w->SetCursor( 'insert +1l linestart' );
    }
}

sub vi_n_q {
    my ($w,$k,$n,$r,$m) = @_;
    die X_NO_MOTION if $m;

    # Completed a mapping
    if( defined $w->{VI_RECORD_REGISTER} ) {
        # Remove this 'q'
        chop $w->{VI_RECORD_KEYS};
        $w->{VI_REGISTER}{ $w->{VI_RECORD_REGISTER} } = $w->{VI_RECORD_KEYS};
        $w->{VI_RECORD_REGISTER} = undef;
    }
    else {
        die X_NO_KEYS if $k eq '';
        die X_BAD_STATE if $k =~ /[_:.%#]/;

        $w->{VI_RECORD_KEYS} = '';
        $w->{VI_RECORD_REGISTER} = $k;
    }
}

sub vi_n_r {
    my ($w,$k,$n,$r,$m) = @_;
    die X_NO_MOTION if $m;
    die X_NO_KEYS if $k eq '';

    $n ||= 1;
    die X_BAD_STATE if $w->compare("insert +$n c",'>','insert lineend');

    if( uc $w->{VI_MODE} eq 'V' ) {
        my $start = $w->index('sel.first');
        my $text = $w->get( $start, 'sel.last' );
        $text =~ s/./$k/g;  # no /s newlines stay intact!
        $w->delete( $start, 'sel.last' );
        $w->insert( $start, $text );
        $w->SetCursor( 'sel.first' );
    }
    else {
        # Grrr.  Tk::Text moves the mark when I want to insert after it.
        my $pos = $w->index('insert');
        $w->delete('insert', "insert +$n c");
        $w->insert('insert',$k x $n);
        $w->SetCursor( $pos );
    }
}

sub vi_n_t {
    my ($w,$k,$n,$r,$m) = @_;

    die X_NO_KEYS if $k eq '';

    my $line = $w->get( 'insert', 'insert lineend' );
    my $ofst = index $line, $k, 1;
    for (2 .. $n) {
        return if $ofst == -1;
        $ofst = index $line, $k, $ofst+1;
    }

    return if $ofst == -1;
    return [ "insert +$ofst c -1c", 'char', 'inc' ];
}

# At the moment, the undo feature is a bit hacky.  The first undo
# removes the undo glob created for the u command itself.
#
sub vi_n_u {
    my ($w,$k,$n,$r,$m) = @_;
    $w->undo;
    $w->undo;
}

sub vi_n_v {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;
    $w->viMode('v');
    $w->{VI_VISUAL_START} = $w->index('insert');
}

sub vi_n_y {
    my ($w,$k,$n,$r,$m) = @_;
    my($start,$end,$wise,$type);
    die X_BAD_STATE if $m;

    # In a visual mode we just need the selection
    if( $w->{VI_MODE} eq 'v' ) {
        $start = 'sel.first';
        $end = 'sel.last';
        $wise = 'char';
        $type = 'exc';
    }
    elsif( $w->{VI_MODE} eq 'V' ) {
        $start = 'sel.first';
        $end = 'sel.last';
        $wise = 'line';
    }
    # In normal mode there's more work
    else {
        # Special case, dd = delete line
        if( $k eq 'y' ) {
            $start = 'insert';
            $end = 'insert';
            $end .= '+' . ($n-1) . 'l' if $n > 1;
            $wise = 'line';
        }
        else {
            my $res = EvalKeys( @_[0 .. 3], 1 );

            $start = 'insert';
            ($end,$wise,$type) = @$res;
        }
    }

    # Swap start and end if the motion was backwards
    if( $w->compare( $start, '>', $end ) ) {
        ($start,$end) = ($end,$start);
        $type = 'exc';                      # XXX: hack
    }

    if( $wise eq 'line' ) {

        $start .= ' linestart';     # From start of line
        $end .= ' lineend +1c';     # Including the \n of the final line
    }
    else {
        $end .= ' +1c' if $type eq 'inc';
    }

    my $text = $w->get( $start, $end );

    if( not defined $r ) {
        $r = '0';
    }

    $w->registerStore( $r, $text );
}

sub vi_n_G {
    my ($w,$k,$n,$r,$m) = @_;

    return [ "$n.0", 'line' ] if $n;
    return [ 'end -1l linestart', 'line' ];
}

sub vi_n_O {
    my ($w,$k,$n,$r,$m) = @_;
    die X_NO_MOTION if $m;
    $w->insert('insert linestart',"\n");
    $w->SetCursor('insert -1l');
    $w->viMode('i');
}

sub vi_n_V {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;

    $w->viMode('V');
    $w->{VI_VISUAL_START} = $w->index('insert');
    $w->tagAdd( 'sel', 'insert linestart', 'insert lineend' );
}

sub vi_n_backtick {
    my ($w,$k,$n,$r,$m) = @_;

    die X_NO_KEYS if $k eq '';

    return unless $w->markExists( "VI_MARK_$k" );

    return [ "VI_MARK_$k", 'char', 'exc' ];
}

sub vi_n_at {
    my ($w,$k,$n,$r,$m) = @_;
    $n ||= 1;

    die X_NO_MOTION if $m;
    die X_NO_KEYS if $k eq '';

    my $keys = $w->registerGet( $k );
    die X_BAD_STATE unless defined $keys;

    my @keys = split //, $keys;

    $w->{VI_PENDING} = '';
    local $_;
    while( $n > 0 ) {
        $n--;
        $w->InsertKeypress($_) for @keys;
    }

    # Any remaining keys should stay in the buffer
    die X_NO_KEYS;
}

sub vi_n_dollar {
    my ($w,$k,$n,$r,$m) = @_;

    $n ||= 1;
    $n--;

    my $i0 = $w->index( "insert +$n l lineend" );
    # Special case, blank line
    return [ "insert +$n l", 'char', 'exc' ] if $i0 =~ /\.0$/;
    return [ "insert +$n l lineend -1c", 'char', 'inc' ];
}

# All the things a % can match
my %brace_left = qw" ( ) { } [ ] ";
my %brace_right = qw" ) ( } { ] [ ";
my $brace_re = join '|', map quotemeta, %brace_left;
$brace_re = qr/($brace_re)/;

sub vi_n_percent {
    my ($w,$k,$n,$r,$m) = @_;
    
    # If passed a count, goes to % in file instead
    if( $n != 0 ) {
        return if $n > 100;
        my $line = int $w->index('end');
        $line *= $n / 100.0;
        $line = (int $line) || 1;
        return [ "$line.0", 'line' ];
    }

    # Find the first bracket-like char on the line after the cursor
    my $line = $w->get( 'insert', 'insert lineend' );
    return unless( $line =~ $brace_re );
    my $brace = $1;
    my $ofst = "insert + $-[0] c";

    # Only care about matching up this brace pair
    # Don't worry about constructs like ( { )
    my $match;
    my $dir;
    my $count = 0;
    my $open = 1;
    if( exists $brace_left{$brace} ) {
        $match = $brace_left{$brace};
        $dir = '+';
    }
    else {
        $match = $brace_right{$brace};
        $dir = '-';
    }
    
    while( $open ) {
        $count++;
        my $char = $w->get( "$ofst $dir $count c" );
        $open++ if( $char eq $brace );
        $open-- if( $char eq $match );

        # XXX: Yuck.  Tk::Text doesn't give us an undef or an error if
        # the index is outside the body of the text, it just gives the first
        # or last index.  This algorithm should really be changed to
        # a linewise one because this is #### inefficient.
        return if $open && $w->compare( "$ofst $dir $count c", '==', '1.0' );
        return if $open && $char eq '' ;
    }

    # XXX: I think % becomes linewise if we crossed a \n    
    return [ "$ofst $dir $count c", "char", "inc" ];
}


sub vi_n_colon {
    my ($w,$k,$n,$r,$m) = @_;
    die X_BAD_STATE if $m;

    $w->viMode('c');
}

sub vi_n_fslash {
    my ($w,$k,$n,$r,$m) = @_;

    # Remember the current location.
    $w->{VI_SAVE_CURSOR} = $w->index('insert');

    # Switch to incremental search mode
    $w->viMode('/');
}

sub vi_fslash {
    my ($w) = @_;

    $w->tagRemove( 'VI_SEARCH', '1.0', 'end' );

    my $re = eval { qr/$w->{VI_PENDING}/ };

    # Regex is incomplete
    return [ $w->{VI_SAVE_CURSOR} ] if $@;

    # XXX: OUCH!  maybe we could scan the regex for \n and
    # (?s) sequences and scan line by line instead?
    my $text = $w->get( $w->{VI_SAVE_CURSOR}, 'end' );
    if( $text =~ $re ) {
        $w->tagAdd( 'VI_SEARCH', "$w->{VI_SAVE_CURSOR} + $-[0] c", "$w->{VI_SAVE_CURSOR} + $+[0] c" );
        return [ "$w->{VI_SAVE_CURSOR} + $-[0] c" ];
    }
    else {
        return [ $w->{VI_SAVE_CURSOR} ];
    }
}

sub vi_fslash_end {
    my ($w) = @_;

    $w->tagRemove( 'VI_SEARCH', '1.0', 'end' );

    my $re = eval { qr/$w->{VI_PENDING}/ };

    # Regex is incomplete
    return if $@;

    # XXX: OUCH!  maybe we could scan the regex for \n and
    # (?s) sequences and scan line by line instead?
    my $text = $w->get( '1.0', 'end' );
    while( $text =~ /$re/g ) {
        $w->tagAdd( 'VI_SEARCH', "1.0 + $-[0] c", "1.0 + $+[0] c" );
    }

    $w->{VI_SEARCH_LAST} = $re;
}

# COMMAND MODE ###########################################################

=begin comment

sub vi_c_ {
    my ($w,$force,$arg) = @_;
}

=cut

sub vi_c_quit {
    my ($w,$force,$arg) = @_;

    $w->Callback( '-systemcommand', 'quit', $w );
}

sub vi_c_map {
    my ($w,$force,$arg) = @_;

    my ($seq,$cmd) = split / +/, $arg, 2;

    $w->viMap( 'nv', $seq, \$cmd ) or $w->setError( 'Ambiguous mapping' );
}

sub vi_c_nohlsearch {
    my ($w,$force,$arg) = @_;

    $w->tagRemove( 'VI_SEARCH', '1.0', 'end' );
}

sub vi_c_split {
    my ($w,$force,$arg) = @_;

    my $newwin = $w->Callback( '-systemcommand', 'split' );
    return if not defined $newwin;

    if( ref $newwin ) {
        $w->vi_split( $newwin );
    }
    else {
        $w->setErr( $newwin );
    }
}

1;

=head1 NAME

Tk::TextVi - Tk::Text widget with Vi-like commands

=head1 SYNOPSIS

    use Tk::TextVi;

    $textvi = $window-E<gt>TextVi( -option =E<gt> value, ... );

=head1 DESCRIPTION

Tk::TextVi is a Tk::TextUndo widget that replaces InsertKeypress() to handle user input similar to vi.  All other methods remain the same (and most code should be using $text->insert( ... ) rather than $text->InsertKeypress()).  This only implements the text widget and key press logic; the status bar must be drawn by the application (see TextViDemo.pl for an example of this).

Functions in Vi that require interaction with the system (such as reading or writing files) are not (currently) handled by this module (This is a feature since you probably don't want :quit to do exactly that).

The cursor in a Tk::Text widget is a mark placed between two characters.  Vi's idea of a cursor is placed on a non-newline character or a blank line.  Tk::TextVi treats the cursor as on (in the Vi-sense) the characters following the cursor (in the Tk::Text sense).  This means that $ will place the cursor just before the final character on the line.

=head2 Options

=over 4

=item -statuscommand

Callback invoked when the mode or the keys in the pending command change.  The current mode and pending keys will be passed to this function.

=item -messagecommand

Callback invoked when messages need to be displayed.

=item -errorcommand

Callback invoked when error messages need to be displayed.

=item -systemcommand

Callback invoked when the parent application needs to take action.  If you return 'undef' the widget will pretend that command doesn't exist and do nothing.  Currently, the argument can be:

    'quit'      The :quit command has been entered
    'split'     :split (see EXPERIMENTAL FEATURES below)

=head2 Methods

All methods present in Tk::Text and Tk::TextUndo are inherited by Tk::TextVi.  Additional or overridden methods are as follows:

=over 4

=item $text->InsertKeypress( $char );

This replaces InsertKeypress() in Tk::Text to recognise vi commands.

=item $text->SetCursor( $index );

This replaces SetCursor() in Tk::Text with one that is aware of the visual selection.

=item $text->viMode( $mode );

Returns the current mode of the widget:

    'i'     # insert
    'n'     # normal
    'c'     # command
    'v'     # visual character
    'V'     # visual line

There is also a fake mode:

    '/'     # Incremental search

If the 'q' command (record macro) is currently active, a q will be appended to the mode.

If the $mode parameter is supplied, it will set the mode as well.  Any pending keystrokes will be cleared (this brings the widget to a known state).

=item $text->viPending;

Returns the current buffer of pending keystrokes.  In normal or visual mode this is the pending command, in command mode this is the partial command line.

=item $text->viError;

Returns a list of all pending error messages.

=item $text->viMessage;

Returns a list of all pending non-error messages (for example the result of normal-ga)

=item $text->viMap( $mode, $sequence, $ref, $force )

$mode should be one of qw( n c v ) for normal, command and visual mode respectively.  Mappings are shared between the different visual modes.  $sequence is the keypress sequence to map the action to.  To map another sequence of keys to be interpreted by Tk::TextVi as keystrokes, pass a scalar reference.  A code reference will be called by Tk::Text (the signature of the function is described below).  A hash reference can be used to restore several mappings (as described below).  If $ref is the empty string the current mapping is deleted.

The function may fail--returning undef--in two cases:

=over 4

=item *

You attempt to map to a sequence that begins another command (for example you cannot map to 'g' since there is a 'ga' command).  Setting $force to a true value will force the mapping and will remove all other mappings that begin with that sequence.

=item *

You attempt to map to a sequence that starts with an existing command (for example, you cannot map to 'aa' since there is an 'a' command).  Setting $force to a true value will remove the mapping that conflicts with the requested sequence.

=back

=back

=head2 Bindings

All bindings present in Tk::Text are inherited by Tk::TextVi.  Do not rely on this as these bindings will be replaced once the vi meaning of those keystrokes is implemented.

=head1 COMMANDS

=head2 Supported Commands

=head3 Normal Mode

    a - enter insert mode after the current character
    d - delete over 'motion' and store in 'register'
        dd - delete a line
    f - find next occurrence of 'character' on this line
    g - one of the two-character commands below
        ga - print ASCII code of character at cursor
        gg - go to the 'count' line
    h - left one character on this line
    i - enter insert mode
    j - down one line
    k - up one line
    l - right one character on this line
    m - set 'mark' at cursor location
    n - next occurrance of last match
    o - open a line below cursor 
    p - insert contents of 'register'
    q - record keystrokes
    r - replace character
    t - move one character before the next occurrence of 'character'
    u - undo
    v - enter visual mode
    x - delete character
    y - yank over 'motion' into 'register'
        yy - yank a line

    D - delete until end of line
    G - jump to 'count' line
    O - open line above cursor
    V - enter visual line mode

    0 - go to start of current line
    @ - execute keys from register
    ` - move cursor to 'mark'
    $ - go to last character of current line
    % - find matching bracketing character
    : - enter command mode
    / - search using a regex

NOTE: The / command is different from Vi in that is uses a perl-style regular expression.

=head3 Visual Mode

Normal-mode motion commands will move the end of the visual area.  Normal-mode commands that operate over a motion will use the visual selection.

There are currently no commands defined specific to visual mode.

=head3 Command Mode

    :map sequence commands
        - maps sequence to commands
    :noh
    :nohl
    :nohlsearch
        - clear the highlighting from the last search
    :split
        - split the window
    :quit
    :q
        - signal quit

=head2 EXPERIMENTAL COMMANDS

=head3 :split

First, :split is only included as a "look at this cool feature" do not count on it to work the same way in the future, or work at all now.  It doesn't even support the ":split file" syntax.  The current implementation is a bit memory-intensive and slows many basic methods of the Tk::Text widget (don't use :split and you won't get penalized).

Second, none of the supporting commands are implemented.  :quit will not close only one window, and there are no Normal-^W commands.

When the -systemcommand callback receives the 'split' action, it should return a new Tk::TextVi widget to the caller or a string to be used as an error message.  The module will copy the contents and make sure all the changes in the text are visible in both widgets.

=head2 WRITING COMMANDS

Perl subroutines can be mapped to keystrokes using the viMap() method described above.  Normal and visual mode commands receive arguments like:

    my ( $widget, $keys, $count, $register, $wantmotion ) = @_;

Where $widget is the Tk::TextVi object, $keys are any key presses entered after those that triggered the function.  Unless you've raised X_NO_KEYS this should be an empty string.  $count is the current count, zero if none has been set.  $register contains the name of the entered register.  $wantmotion will be a true value if this command is being called in a context that requires a cursor motion (such as from a d command).

Commands receive arguments in the following format:

    my ( $widget, $forced, $argument ) = @_;

$forced is set to a true value if the command ended with an exclamation point.  $argument is set to anything that comes after the command.

To move the cursor a normal-mode command should return an array reference.  The first parameter is a string representing the new character position in a format suitable to Tk::Text.  The second is either 'line' or 'char' to specify line-wise or character-wise motion.  Character-wise motion should also specific 'inc' or 'exc' for inclusive or exclusive motion as the third parameter.

Scalar references will be treated as a sequence of keys to process.  All other return values will be ignored, but avoid returning references (any future expansion will use leave plain scalar returns alone).

=head3 Exceptions

=item X_NO_MOTION

If a true value is passed for $wantmotion and the function is not a motion command, die with this value.

=item X_NO_KEYS

Use when additional key presses are required to complete the command.

=item X_BAD_STATE

For when the command can't complete and panic is more appropriate than doing nothing.

=head3 Methods

=item $text->EvalKeys( $keys, $count, $register, $wantmotion )

Uses keys to determine the function to call passing it the count, register and wantmotion parameters specified.  The return value will be whatever that function returns.  If wantmotion is a true value the return value will always be an array reference as described above.

Normally you want to call this function like this, passing in the set of keystrokes after the command, the current count, the current register and setting wantmotion to true:

    $w->EvalKeys( @_[1..3], 1 )

=item $text->setMessage( $msg )

Queue a message to be displayed and generate the associated event.

=item $text->setError( $msg )

Same as setMessage, but the message is added to the error list and the error message event is generated.

=item $text->registerStore( $register, $text )

Store the contents of $text into the specified register.  The text will also be stored in the unnamed register.  If the '*' register is specified, the clipboard will be used.  If the black-hole or a read-only register is specified nothing will happen.

=item $text->registerGet( $register )

Returns the text stored in a register

=head1 BUGS

If you find a bug in the handling of a vi-command, please try to produce an example that looks something like this:

    $text->Contents( <<END );
    Some
    Initial
    State
    END

    $text->InsertKeypress( $_ ) for split //, 'commands in error';

Along with the expected final state of the widget (contents, cursor location, register contents etc).

If the bug relates to the location of the cursor after the command, note the difference between Tk::Text cursor positions and vi cursor positions described above.  The command may be correct, but the cursor location looks wrong due to this difference.

=head2 Known Bugs

=over 4

=item *

Using the mouse or $text->setCursor you place illegally place the cursor after the last character in the line.

=item *

Counts are not implemented on insert commands like normal-i or normal-o.

=item *

Commands that use mappings internally (D and x) do not correctly use the count or registers.

=item *

Normal-/ should behave like a motion, but doesn't.

=item *

Normal-/ and normal-n will not wrap after hitting end of file.

=item *

Normal-u undoes individual Tk::Text actions rather than vi-commands.

=item *

This modules makes it much easier to commit the programmer's third deadly sin.

=back

=head1 AUTHOR

Joseph Strom, C<< <j-strom.verizon.net> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Joseph Strom, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
