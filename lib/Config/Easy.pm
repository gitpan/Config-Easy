use strict;
package Config::Easy;
use Carp qw/croak/;

our $VERSION = "0.1";
our %C;
my ($fname, $fromfile, $atline, $expanded);
use constant STRICT => " strict";        # key for strict_hash emulation
                                         # the leading space makes sure
                                         # that it won't collide with another.

sub import {
    my ($call_pkg, $call_file, $call_line) = caller;
    {
        #
        # export %C to the caller's package
        #
        unless ($fromfile) {
            $fromfile = $call_file;
            $atline = $call_line;
        }
        no strict 'refs';
        *{"$call_pkg\::C"} = \%C;
        *{"$call_pkg\::config_eval"} = \&config_eval;
    }
    my $module = shift;
    #
    # give warnings
    # if we either have already processed
    # a configuration file and we were given another one
    # OR
    # if we weren't given one and we need one.
    #
    if (@_) {
        if ($fname) {
            my $extra_fname = shift;
            die "In $call_file at line $call_line ",
                "there is no need to say:\n\n  ",
                "use Config::Easy '$extra_fname';\n\n",
                "Simply say:\n\n",
                "  use Config::Easy;\n\n",
                "We have already processed '$fname' in $fromfile ",
                "at line $atline.\n\n";
        } else {
            $fname = shift; # normal case
        }
    } else {
        if ($fname) {
            return;         # normal case
        } else {
            die "Config::Easy: Must provide a default configuration file.\n";
        }
    }

    #
    # is there a command line option -F with a filename?
    # it will override any $fname above.
    #
    for (my $i = 0; $i < @ARGV; ++$i) {
        if ($ARGV[$i] =~ /^-F/) {
            my $n;
            if ($ARGV[$i] =~ /^-F(\w+)/) {
                $n = 1;
                $fname = $1;
            } else {
                if ($fname = $ARGV[$i+1]) {
                    $n = 2;
                } else {
                    die "missing file name after -F!\n";
                }
            }
            splice @ARGV, $i, $n;
			last;
        }
    }
    _init();
    args();
    expand();
}

sub new {
    my ($pkg, $file) = @_;

    die "Must supply filename to Config::Easy->new\n"
        unless $file;
    $fname = $file;
    my $self = {};
    $self->{STRICT} = 1;
    _init($self);
    return bless $self, $pkg;
}

#
# enforce the strict hash for this Config::Easy object
#
sub strict {
    my ($self) = shift;
    $self->{STRICT} = 1;
}

#
# relax the strict hash for this Config::Easy object
#
sub no_strict {
    my ($self) = shift;
    $self->{STRICT} = 0;
}

sub get {
    my ($self) = shift;

    expand($self) unless $expanded;
    if (@_ and $self->{STRICT}) {
        for my $key (@_) {
            croak "key '$key' does not exist"
                unless exists $self->{$key};
        }
    }
    return (@_)? @{$self}{@_}:        # wow!
                 %{$self};
}

#
# we have already set $fname - one way or another
#
sub _init {
    my ($self) = @_;        # may be set or not
    open IN, $fname or die "cannot open $fname: $!\n";
    my ($k, $v, $contline, $delim);
    local $_;        # in case it is used elsewhere!
    while (<IN>) {
        chomp;
        s/^\s*//;               # trim leading blanks
        s/(?<!\\)#.*//;         # trim unescaped comments
        next unless /\S/;       # skip entirely blank lines
        # process continuation lines
        while (s/(\s*)\\\s*$/(length($1) >= 1)? " ": ""/e) {
            $contline = <IN>;
            last unless defined $contline;
            $contline =~ s/^\s*//;          # trim leading blanks
            $contline =~ s/(?<!\\)#.*//;    # trim comments
            $_ .= $contline;
        }
        ($k, $v) = split /\s+/, $_, 2;
        if ($v eq "-") {
            $v = "";
            while (<IN>) {
                last if /^\./;
                s/[ \t]+$//;    # trim trailing tab/space not newline
                $v .= $_;
            }
            $v = _process($v, 1);    # add a new line if not a 
                                    # reference or a quoted string
            if ($self) {
                $self->{$k} = $v;
            } else {
                $C{$k} = $v;
            }
            next;
        }
        #
        # do we need to get more lines to satisfy
        # an unmatched leading ', ", [ or { in the value?
        #
        $delim = substr $v, 0, 1;
        $delim =~ tr/[{/]}/;
        if ((index qq!'"]}!, $delim) >= 0
            and $v !~ /$delim\s*$/)
        {
            $v .= "\n";        # add back the newline we chomped
            while (1) {
                $contline = <IN>;
                last unless defined $contline;
                $contline =~ s/(?<!\\)#.*//;    # trim comments
                $v .= $contline;
                last if $v =~ /$delim\s*$/;
            }
        }
        $v = _process($v);
        if ($self) {
            $self->{$k} = $v;
        } else {
            $C{$k} = $v;
        }
    }
    close IN;
}

#
# get overriding key=value pairs on the command line
#
sub args {
    my ($self) = @_;        # may be set or not
    my ($arg, @NEWARGV);
    my ($k, $v);

    while ($arg = shift @ARGV) {
        if ($arg eq "--") {
            push @NEWARGV, "--", @ARGV;
            last;
        }
        if (($k, $v) = $arg =~ /^(.*)=(.*)$/) {
            warn "warning: no '$k' key in config file to override\n"
                unless ($self)? exists $self->{$k}:
                                exists $C{$k};
            $v = _process($v);
            if ($self) {
                $self->{$k} = $v;
            } else {
                $C{$k} = $v;
            }
        } else {
            push @NEWARGV, $arg;
        }
    }
    @ARGV = @NEWARGV;
}

#
# substitute definitions for unescaped $vars
# this is the first time I've used (needed)
# a negative lookbehind assertion!
# we needed it to provide for a real dollar sign by
# escaping it.
#
sub expand {
    my ($self) = @_;
    my $href = $self || \%C;
    for my $k (keys %$href) {
        $href->{$k} =~ s/(?<!\\)\$(\w+)
                        /(exists $href->{$1})? $href->{$1}: ""
                        /xeg;
		$href->{$k} =~ s/\\([\$#])/$1/g;              # \$ to $ and \# to #
    }
	$expanded = 1;
}

sub _process {
    my ($v, $newline) = @_;

    $v =~ s/\s*$//;                      # trim trailing blanks

    if    ($v =~ /^\s*\[\s*(.*?)\s*\]$/sm) {  # ref to anonymous array
        return [ split /\s+/, $1 ];
    }
    elsif ($v =~ /^\s*\{\s*(.*?)\s*\}$/sm) {  # ref to anonymous hash
        return { split /\s+/, $1 };
    }
    elsif ($v =~ /^\s*(["'])(.*)\1$/sm) {     # quoted with matching " or '
        return $2;
    } else {
        $v .= "\n" if $newline;
        return $v;
    }
}

sub config_eval {
    my $self;
    $self = shift if ref $_[0];        # called as method or not?
    no strict 'refs';
	my $href = $self || \%C;
	@_ = keys %$href unless @_;
    package main;        # how to use caller's package?
    for my $k (@_) {
		$href->{$k} =~ s/\$(\w+)/${$1}/eg;
	}
    use strict 'refs';
}

1;

=head1 NAME
    
Config::Easy - Access to a simple key-value configuration file.

=head1 SYNOPSIS

Typical usage:

  conf.txt contains:
  -------
  # vital information
  name       Harriet
  city       San Francisco

  # options
  verbose    1        # 0 or 1
  -------

  use Config::Easy 'conf.txt';

  print "$C{name}\n" if $C{verbose};

Or for an object oriented approach:

  use Config::Easy();

  my $c = Config::Easy->new('conf.txt');

  print $c->get('name'), "\n"
    if  $c->get('verbose');

For more details see the section OBJECT.

=head1 DESCRIPTION

The statement:

  use Config::Easy "conf.txt";

will take the file named "conf.txt" in the current
directory as the default configuration file.

Lines from the file have leading and trailing blanks trimmed.
Comments begin with # and continue to the end of the line.
Entirely blank lines are ignored.

Lines are divided into key and value at the first
white space on the line.   These key-value pairs are inserted
into the %C hash which is then exported into the current package.

  # personal information
  empname     Harold
  ssn         123-45-6789
  phone       876-555-1212

  print "$C{empname} - $C{ssn}\n";

The name is the minimal %C to visually emphasize the key name.

The file 'conf.txt' can be overridden with a -F command line option.

  % prog -F newconf 

It can also be C<-Fnewconf>, if you wish.

To use a configuration file in the same directory as
the perl script itself you can use the core module FindBin:

  use FindBin;
  use Config::Easy "$FindBin::Bin/conf.txt";

=head1 COMMAND LINE ARGUMENTS

Command line arguments are scanned looking for any with
an equals sign in them.

  % prog name=Mathilda status=okay

These arguments are extracted (removed from @ARGV),
parsed into key=value and inserted into the %C hash.
They will override any values in the configuration file.
A warning is emitted if the key did not appear in the file.

This parsing of arguments will stop at an argument of '--'.

  % prog name=Mary -- num=3

'-- num=3' can be processed by 'prog' itself.

=head1 ACCESS ELSEWHERE

If you want access to the configuration hash from
other files simply put:

  use Config::Easy;

at the top of those files; the %C hash will again
be exported into the current package.  You need to have:

  use Config::Easy 'conf.txt';

only once in the main file before anyone needs to look
at the $C hash.

=head1 STRICT

Installing the module Tie::StrictHash will protect against
the common problem of misspelling of a key name:

  use Config::Easy 'conf';
  use Tie::StrictHash;
  strict_hash %C;

  print "name is $C{emplname}\n";

  % prog
  key 'emplname' does not exist at prog line 5
  %

If there is access from other files you need
the strict_hash call only in the main file.

=head1 CONTINUATION LINES

Lines ending with backslash are continued
onto the next line.  This allows:

  ids   45 \
        67 \    # middle value
        89

instead of:

  ids    45 67 89

Leading blanks on continuation lines are trimmed.
Any blanks before the backslash are converted to a single blank.

=head1 STRING SUBSTITUTION

For a simple string substitution mechanism:

  name        Harold
  place       here
  phrase      I'm $name and I'm $place.

This would yield:

  $C{phrase} = "I'm Harold and I'm here.";

You can escape an actual dollar sign with a backslash '\'.

There is also a way to interpolate I<your> (or rather I<our>) variables into
a configuration value.

In the configuration file:

  path        /a/b/c.\$date.gz      # the dollar sign is escaped

In the code:

  print $C{path};       #   /a/b/c.$date.gz
  our $date = "20040102";
  config_eval;
  print $C{path};       #   /a/b/c.20040102.gz

The exported function 'config_eval' will interpolate
'our' (not 'my') variables from the main package into the %C values.   
You can give config_eval a list of which keys to evaluate, if you wish.

  config_eval qw/path trigger/;

=head1 QUOTED VALUES

Leading and trailing blanks in the value are normally trimmed.
If you I<do> want such things
quote the value field with single or double quotes.
The quotes will be trimmed off for you.

  foo     "   big one   "
  bar     ' yeah '

If you want an actual # in the value escape it
with a backslash.

  title   The \# of hits.

=head1 MULTIPLE VALUES

Multiple valued values are possible by
using references to anonymous arrays and hashes.
This syntax in the configuration file:

  colors [ red yellow blue green ]

will effectively do this:

  $C{colors}  = [ qw(red yellow blue green) ];

In your program you can have:

  for my $c (@{$C{colors}}) {
      ...
  }

or

  print $C{colors}[2];

Similarily:

  ages  { joe   45 \
          betty 47 \
          mary  13 \       # their daughter
        }

does this:

  $C{ages} = { joe   => 45,
               betty => 47
               mary  => 13,
             };

In both cases neither the values nor the keys can have internal blanks.
If you need this you could use underscores for this purpose
and replace them with blanks later.

If a value begins with ', ", [, or { and does
not end with the matching delimiter then further
lines will be read until such a line is found.
This makes the syntax cleaner and more maintainable:

  ages {
      joe   45
      betty 47
      mary  13       # their daughter
  }

=head1 MULTI-LINE VALUES

If you wish a single value to span multiple lines:

  story -
  Once upon  a time
  there was a fellow named
  $name who lived peacefully
  in the town of $city.
  .

If the value is '-' alone, it indicates that the real
value is all following lines up until a period '.' is seen on
a line by itself.  String substitution will still take
place.  $C{story} from above will have 4 embedded newlines.

=head1 OBJECT

Some may object to their namespace being 'polluted' with the
%C hash or find the name %C too cryptic.
They also may not like command line arguments being parsed
and extracted by any module except those named Getopt::*.

For these users there is a pure object oriented interface:

  use Config::Easy();    # the () is required so that
                         # nothing is done at import() time.
  my $c = Config::Easy->new('conf.txt');

  $c->args;        # parse command line arguments (optional)

  #
  # the get method can be called in several ways
  #
  print "name is ", $c->get('name'), "\n";          #  the key 'name'

  my ($age, $status) = $c->get(qw/ age status /);   # two at once

  my %config = $c->get;                             # gets entire hash
  print $config{name};

You I<can> have multiple instances of the Config::Easy object.

The get method enforces 'strict' behavior.  If you use
a key name that does not occur in the configuration file
it will die with an error message.

  print $c->get("oops");

  % prog
  key 'oops' does not exist at prog line 10.

Methods 'strict' and 'no_strict' turn this behavior on and off.

'config_eval' is a method to interpolate 'our' variables.  See
STRING SUBSTITUTION above.

=head1 SEE ALSO

Tie::StrictHash protects against misspelling of key names.

Getopt::Easy is a clear and simple alternative
to Getopt::Std and Getopt::Long.

Date::Simple is an elegant way of dealing with dates.

=head1 AUTHOR

Jon Bjornstad <jon@icogitate.com>

=cut
