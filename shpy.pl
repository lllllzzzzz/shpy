#!/usr/bin/perl

use warnings;
use strict;

my %operators = (
    "-lt" => "<",
    "-le" => "<=",
    "-gt" => ">",
    "-ge" => ">=",
    "-eq" => "==",
    "-ne" => "!="
);

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

sub get_words {
    my $str = shift;
    return split(' ', $str);
}

sub get_list {
    my $str = shift;
    my @words = split(" ", $str);
    my @list;

    foreach my $i (0 .. $#words) {
        # Enclose variables in str() e.g. $i => str(i)
        if ($words[$i] =~ /^\$/) {
            $words[$i] =~ s/\$//g;
            $list[$i] = "str($words[$i])";
        } else {
            $list[$i] = "'" . $words[$i] . "'";
        }
    }
    
    return join(", ", @list);
}

sub do_if_while {
    my $line = shift;
    $line =~ s/\$#/len(sys.argv[1:])/g;
    my @args = get_words($line);

    if ($args[0] eq "else") {
        print "$args[0]:\n";
    }

    # Parse "while true"
    elsif ($args[1] =~ "true|false" && $#args == 1) {
        print("while not subprocess.call(['$args[1]']):\n");
    }

    # Parse grep/fgrep
    elsif ($args[1] =~ /grep|fgrep/) {
        # Remove first word ("if") from line.
        $line =~ s/^\s*\S+\s*//;
        
        if ($args[1] eq "grep") {
            printf("$args[0] subprocess.call([%s]):\n", get_list($line));
        } else {
            printf("$args[0] not subprocess.call([%s]):\n", get_list($line));
        }
    }

    elsif ($args[1] eq "test") {
        $line =~ s/\$//g;
        my @args = get_words($line);        

        if ($args[2] eq "-r" && $#args == 3) {
            printf("%s os.access('%s', os.R_OK):\n", $args[0], $args[3]);
        } elsif ($args[2] eq "-d" && $#args == 3) {
            printf("%s os.path.isdir('%s'):\n", $args[0], $args[3]);
        } elsif ($args[3] eq "=" && $#args == 4) {
            printf("%s '%s' == '%s':\n", $args[0], $args[2], $args[4]);
        } elsif ($args[3] =~ /lt|le|gt|ge|eq|ne/) {
            print "$args[0] int($args[2]) $operators{$args[3]} int($args[4]):\n";
        }
    }

    elsif ($args[1] eq "[" && $args[$#args] eq "]") {
        $line =~ s/\$//g;
        my @args = get_words($line);

        if ($args[2] eq "-d") {
            printf("$args[0] os.path.isdir('%s'):\n", $args[3]);
        } elsif ($args[3] =~ /lt|le|gt|ge|eq|ne/) {
            print "$args[0] int($args[2]) $operators{$args[3]} int($args[4]):\n";
        }
    }
}

sub do_for {
    my $line = shift;
    my @oldLine = split(' ', $line);

    if ($#oldLine > 1) {
        my @newLine;

        # Parsing a wilcard?
        # e.g. *.c, *.h
        if ($line =~ /\*\.[A-Za-z]+/) {
            printf("for %s in sorted(glob.glob('%s')):\n", $oldLine[1], $oldLine[3]);
        } else {
            # Extract variable from for loop.
            my $forLoopVar = $oldLine[1];

            # Build array from for loop variables.
            $newLine[$_ - 3] = "'" . $oldLine[$_] . "'" for (3 .. $#oldLine);

            # Convert this array to a string and output.
            my $list = join(', ', @newLine);
            printf("for %s in %s:\n", $oldLine[1], $list);
        }
    }
}

sub do_echo {
    my $line = shift;
    my $fileFound = 0;

    # Extract arguments of echo.
    $line =~ s/^\S+\s*//;    
    my @words = get_words($line);

    my $printNewline = 1;
    # Handle -n flag (do not print newline).
    if ($words[0] eq "-n") {
        $printNewline = 0;
        $line =~ s/^\S+\s*//;
        @words = get_words($line);
    }

    $line =~ s/\$@/sys.argv[1:]/g;

    # Parse variables.
    if ($line =~ /\$[0-9]/ || $line =~ /\$([A-Z]|[a-z]|[0-9]|_)+/) {
        for my $i (0 .. $#words) {
            # $0, $1, ... $9
            if ($words[$i] =~ /\$[0-9]/) {
                $words[$i] =~ s/\$//g;
                $words[$i] = "sys.argv[$words[$i]]";
            # $foo, $bar
            } elsif ($words[$i] =~ /\$([A-Z]|[a-z]|[0-9]|_)+/) {
                $words[$i] =~ s/\$//g;
            # 1, "string"
            } else {
                $words[$i] = "'$words[$i]'";
            }

            # Parse file.
            if ($words[$i] =~ /^>>/) {
                $fileFound = 1;
                $words[$i] =~ s/>>//g;
                $words[$i - 1] =~ s/\$//g;
                print("with open($words[$i], 'a') as f: print >>f, $words[$i - 1]");
            }
        }

        if ($fileFound == 0) {
            printf("print %s", join(', ', @words));
        }

        print(",") if (!$printNewline);
        print("\n");
    }

    # No variables?
    elsif ($line =~ /('|")[^\$]/) {
        printf("print $line");
        print(",") if (!$printNewline);
        print("\n");
    }

    else {
        # Parse variables (regex match for '$').
        if ($line =~ / \$/) {
            print("print $line");
        } else {
            print("print '$line'");
        }

        print(",") if (!$printNewline);
        print("\n")
    }
}

sub do_read {
    my $line = shift;

    # Remove first word ("read") from line.
    $line =~ s/^\s*\S+\s*//;

    printf("%s = ", $line) if (length($line) > 0);
    printf("sys.stdin.readline().rstrip()\n");
}

sub do_cd {
    my $line = shift;

    # Extract directory from line.
    my $dir = $line;
    $dir =~ s/^\s*\S+\s*//;

    # If no directory specified cd to '~'.
    my $arg = (length($dir) > 0) ? $dir : "~";
    print("os.chdir('" . $arg . "')\n");
}

sub do_subprocess {
    my $line = shift;

    if ($line =~ /\$@/) {
        # Remove last word ("$@") from line.
        $line =~ s/\s+\S+\s*$//;
        printf("subprocess.call([%s] + sys.argv[1:])\n", get_list($line));
    } else {
        printf("subprocess.call([%s])\n", get_list($line));
    }    
}

sub do_exit {
    my $line = shift;
    $line =~ s/^\S+\s*//;
    print("sys.exit($line)\n");
}

sub do_variables {
    my $line = shift;
    my $lhs = substr($line, 0, index($line, "="));  # Destination variable.
    my $rhs = substr($line, index($line, "=") + 1); # Source variable/constant.

    # $0, $1 ... $9
    if ($line =~ /\$[0-9]/) {
        $rhs =~ s/\$//g;
        $lhs .= " = sys.argv[" . $rhs . "]\n";
    # $foo, $bar
    } elsif ($line =~ /(\$[A-Z]|[a-z]|[0-9]|_)/) {
        # number=$(($number + 1))
        if ($rhs =~ /^\$\(\(\$/) {
            $rhs =~ s/\$\(\(\$//g;
            $rhs =~ s/\)\)//g;
            my @words = get_words($rhs);
            $words[1] =~ s/\$//g;
            #$rhs =~ s/\$//g;
            $lhs .= " = int($words[0]) $words[1] $words[2]\n";
        # foo=$bar
        } elsif ($rhs =~ /^\$/) {
            $rhs =~ s/\$//g;
            $lhs .= " = $rhs\n";
        # number=`expr $number + 1`
        } elsif ($rhs =~ /`expr/) {
            $rhs =~ s/`//g;
            my @words = get_words($rhs);
            $words[1] =~ s/\$//g;
            $lhs .= " = int($words[1]) $words[2] $words[3]\n";
        # foo=1
        } else {
            $lhs .= " = '" . substr($line, index($line, "=") + 1) . "'\n";
        }
    }

    print("$lhs");
}

sub ltrim {
    my $str = shift;
    $str =~ s/^\s+//g;
    return $str;
}

sub count_leading_whitespace {
    my $str = shift;
    return length($str) - length(ltrim($str));
}

sub get_leading_whitespace {
    my $str = shift;
    my $whitespace = "";
    $whitespace .= " " for (1 .. count_leading_whitespace($str));
    return $whitespace;
}

# Regex strings to match in the translation loop.
# These regexes are used to parse shell code and convert to Python.
my $REGEX_VAR      = "(^[A-Z]|[a-z]|[0-9]|_)=";
my $REGEX_ECHO     = "^echo";
my $REGEX_OS_1     = "\\[ -d";
my $REGEX_OS_2     = "^cd|test -r|test -d";
my $REGEX_READ     = "^read";
my $REGEX_SUB      = "^(ls|pwd|id|date|rm|fgrep|grep)";
my $REGEX_CD       = "^cd";
my $REGEX_IF_WHILE = "^if|elif|else|while";
my $REGEX_FOR      = "^for";
my $REGEX_EXIT     = "^exit";
my $REGEX_IGNORE   = "^do|done|then|fi";
my $REGEX_COMMENT  = "^#";
my $REGEX_SYS_1    = "^exit|read|";
my $REGEX_SYS_2    = "\$@";

my @imports;
my @stdin = <>;

# Process all lines to find packages to import.
for my $nLine (0 .. $#stdin) {
    my $line = ltrim($stdin[$nLine]);

    if ($line =~ /$REGEX_SUB/)   { push @imports, "subprocess"; }
    if ($line =~ /$REGEX_OS_1/)  { push @imports, "os";         }
    if ($line =~ /$REGEX_OS_2/)  { push @imports, "os";         }
    if ($line =~ /$REGEX_SYS_1/) { push @imports, "sys";        }
    if ($line =~ /$REGEX_SYS_2/) { push @imports, "sys";        }
    if ($line =~ /^for/ && $line =~ /\*\.[A-Za-z]+/) {
        push @imports, "glob";
    }
}

#seek STDIN, 0, 0;

#while ($line = <>) {
for my $nLine (0 .. $#stdin) {
    my $line = $stdin[$nLine];
    chomp $line;
    print(get_leading_whitespace($line));
    $line = ltrim($line);

    if ($line =~ /^#!/ && $nLine == 0) {
        print "#!/usr/bin/python2.7 -u\n";
        printf("import %s\n", join(', ', uniq(@imports))) if ($#imports >= 0);
    }

    elsif (length($line) == 0)         { print "\n";           }
    elsif ($line =~ /$REGEX_VAR/)      { do_variables($line);  }
    elsif ($line =~ /$REGEX_ECHO/)     { do_echo($line);       }
    elsif ($line =~ /$REGEX_READ/)     { do_read($line);       }
    elsif ($line =~ /$REGEX_SUB/)      { do_subprocess($line); }
    elsif ($line =~ /$REGEX_CD/)       { do_cd($line);         }
    elsif ($line =~ /$REGEX_IF_WHILE/) { do_if_while($line);   }
    elsif ($line =~ /$REGEX_FOR/)      { do_for($line);        }
    elsif ($line =~ /$REGEX_EXIT/)     { do_exit($line);       }
    elsif ($line =~ /$REGEX_IGNORE/)   {}
    elsif ($line =~ /$REGEX_COMMENT/)  { print("$line\n");     }
    else                               { print("#$line\n");    }
}
