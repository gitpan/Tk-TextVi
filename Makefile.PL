use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Tk::TextVi',
    AUTHOR              => 'Joseph Strom <j-strom@verizon.net>',
    VERSION_FROM        => 'lib/Tk/TextVi.pm',
    ABSTRACT_FROM       => 'lib/Tk/TextVi.pm',
    PL_FILES            => {},
    EXE_FILES           => [ 'bin/TextViDemo.pl' ],
    LICENSE             => 'perl',
    PREREQ_PM => {
        'Test::More' => 0,
        'Tk' => '804.027',
        'Tk::TextUndo' => '4.013',
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Tk-TextVi-*' },
);
