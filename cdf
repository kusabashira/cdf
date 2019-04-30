#!/usr/bin/perl
use strict;
use warnings;
use autouse "Cwd" => qw(abs_path getcwd);
use autouse "File::Basename" => qw(dirname);
use autouse "File::Path" => qw(make_path);
use autouse "JSON::PP" => qw(encode_json decode_json);

my $CDFFILE = $ENV{CDFFILE} // "$ENV{HOME}/.config/cdf/cdf.json";

my $supported_shells = [qw(sh ksh bash zsh yash fish tcsh rc nyagos xonsh)];

my $cmd_name = $0 =~ s/.*\///r;
my $usage = <<EOF;
usage:
  $cmd_name [--] <label>         # chdir to the path so labeled
  $cmd_name -a <label> [<path>]  # save the path with the label
  $cmd_name -g <label>           # get the path so labeled
  $cmd_name -l                   # list labels
  $cmd_name -r <label>           # remove the label
  $cmd_name -w [<shell>]         # output the wrapper script (default: sh)
  $cmd_name -h                   # print usage

supported-shells:
  @{[join ", ", @$supported_shells]}

environment-variables:
  CDFFILE   # the registry path (default: ~/.config/cdf/cdf.json)
EOF

sub read_file {
    my ($path) = @_;
    open my $fh, "<", $path or die $!;
    my $content = do { local $/; <$fh>; };
    close $fh or die $!;
    return $content;
}

sub write_file {
    my ($path, $content) = @_;
    open my $fh, ">", $path or die $!;
    print $fh $content;
    close $fh or die $!;
}

sub main {
    if ((@ARGV == 0) || (@ARGV == 1 && $ARGV[0] eq "--")) {
        print STDERR $usage;
        exit 2;
    }
    if (($ARGV[0] !~ /^-/) || (@ARGV > 1 && $ARGV[0] eq "--")) {
        print STDERR <<"        EOF" =~ s/^ {8}//gmr;
        $cmd_name: shell integration not enabled
        Please add following line to your shell's rc file.

        command -v $cmd_name > /dev/null && eval "\$($cmd_name -w)"

        EOF
        exit 2;
    }

    my $mode = shift @ARGV;

    if ($mode eq "-a") {

        if (@ARGV < 1) {
            print STDERR "$cmd_name: $mode: no input name\n";
            exit 2;
        }
        if (-e $CDFFILE && ! -f $CDFFILE) {
            print STDERR "$cmd_name: $mode: \$CDFFILE should be a file\n";
            exit 2;
        }

        my $label = $ARGV[0];
        my $path  = $ARGV[1] // getcwd;

        if (! -e $CDFFILE) {
            make_path(dirname($CDFFILE));
            write_file($CDFFILE, "{}\n");
        }

        my $pathes = decode_json(read_file($CDFFILE));

        $pathes->{$label} = abs_path($path);

        write_file($CDFFILE, encode_json($pathes) . "\n");

    } elsif ($mode eq "-g") {

        if (@ARGV < 1) {
            print STDERR "$cmd_name: $mode: no input name\n";
            exit 2;
        }
        if (! -e $CDFFILE) {
            print STDERR "$cmd_name: $mode: \$CDFFILE doesn't exists\n";
            exit 2;
        }

        my $label = $ARGV[0];

        my $pathes = decode_json(read_file($CDFFILE));

        if (exists $pathes->{$label}) {
            print "$pathes->{$label}\n";
        } else {
            print STDERR "$cmd_name: $mode: $label: label not found\n";
            exit 1;
        }

    } elsif ($mode eq "-l") {

        if (! -e $CDFFILE) {
            print STDERR "$cmd_name: $mode: \$CDFFILE doesn't exists\n";
            exit 2;
        }

        my $pathes = decode_json(read_file($CDFFILE));

        for my $label (sort { $a cmp $b } keys %$pathes) {
            print "$label\n";
        }

    } elsif ($mode eq "-r") {

        if (@ARGV < 1) {
            print STDERR "$cmd_name: $mode: no input name\n";
            exit 2;
        }
        if (! -e $CDFFILE) {
            print STDERR "$cmd_name: $mode: \$CDFFILE doesn't exists\n";
            exit 2;
        }

        my $label = $ARGV[0];

        my $pathes = decode_json(read_file($CDFFILE));

        delete $pathes->{$label};

        write_file($CDFFILE, encode_json($pathes) . "\n");

    } elsif ($mode eq "-w") {

        my $type = $ARGV[0] // "sh";

        if ($type eq "sh") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            cdf() {
                if [ \$# -eq 0 ]; then
                    command -- cdf
                    return
                elif [ \$# -eq 1 ] && [ "\$1" = "--" ]; then
                    command -- cdf
                    return
                elif [ \$# -ge 1 ] && [ "\$1" != "\${1#-}" ] && [ "\$1" != "--" ]; then
                    command -- cdf "\$@"
                    return
                fi

                if [ "\$1" = "--" ]; then
                    shift
                fi

                set -- "\$(command -- cdf -g "\$1")"
                if [ -n "\$1" ]; then
                    cd "\$1" || return
                fi
            }
            EOF
        } elsif ($type eq "ksh") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            cdf() {
                if [[ \$# -eq 0 || ( \$# -eq 1 && \$1 = -- ) || ( \$# -ge 1 && \$1 = -* && \$1 != -- ) ]]; then
                    command -- cdf "\$@"
                fi

                if [[ \$1 = -- ]]; then
                    shift
                fi

                set -- "\$(command -- cdf -g "\$1")"
                if [[ -n \$1 ]]; then
                    cd "\$1"
                fi
            }
            EOF
        } elsif ($type eq "bash") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            cdf() {
                if [[ \$# -eq 0 || ( \$# -eq 1 && \$1 = -- ) || ( \$# -ge 1 && \$1 = -* && \$1 != -- ) ]]; then
                    command -- cdf "\$@"
                    return
                fi

                if [[ \$1 = -- ]]; then
                    shift
                fi

                local nextpath
                nextpath=\$(command -- cdf -g "\$1")
                if [[ -n \$nextpath ]]; then
                    cd "\$nextpath" || return
                fi
            }

            _cdf() {
                local cur=\${COMP_WORDS[COMP_CWORD]}
                case \$COMP_CWORD in
                    1)
                        case \$cur in
                            -*) COMPREPLY=( \$(compgen -W "-- -a -g -l -r -w -h" -- "\$cur") ) ;;
                            *)  COMPREPLY=( \$(compgen -W "\$(cdf -l)" -- "\$cur") ) ;;
                        esac
                        ;;
                    *)
                        local cmd=\${COMP_WORDS[1]}
                        case \$cmd in
                            --)
                                COMPREPLY=( \$(compgen -W "\$(cdf -l)" -- "\$cur") )
                                ;;
                            -a)
                                case \$COMP_CWORD in
                                    2) COMPREPLY=( \$(compgen -W "\$(cdf -l)" -- "\$cur") ) ;;
                                    *) _filedir -d ;;
                                esac
                                ;;
                            -g)
                                COMPREPLY=( \$(compgen -W "\$(cdf -l)" -- "\$cur") )
                                ;;
                            -l)
                                COMPREPLY=()
                                ;;
                            -r)
                                COMPREPLY=( \$(compgen -W "\$(cdf -l)" -- "\$cur") )
                                ;;
                            -w)
                                COMPREPLY=( \$(compgen -W "@$supported_shells" -- "\$cur") )
                                ;;
                        esac
                        ;;
                esac
            }
            complete -F _cdf cdf
            EOF
        } elsif ($type eq "zsh") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            cdf() {
                if [[ \$# -eq 0 || ( \$# -eq 1 && \$1 = -- ) || ( \$# -ge 1 && \$1 = -* && \$1 != -- ) ]]; then
                    command -- cdf "\$@"
                    return
                fi

                if [[ \$1 = -- ]]; then
                    shift
                fi

                local nextpath
                nextpath=\$(command -- cdf -g "\$1")
                if [[ -n \$nextpath ]]; then
                    cd "\$nextpath" || return
                fi
            }

            _cdf() {
                local cur=\${words[\$CURRENT]}
                case \$CURRENT in
                    2)
                        case \$cur in
                            -*)
                                local modes
                                modes=(
                                "--[chdir to the path so labeled]"
                                "-a[save the path with the label]"
                                "-g[get the path so labeled]"
                                "-l[list labels]"
                                "-r[remove the label]"
                                "-w[output the wrapper script]"
                                "-h[print usage]"
                                )
                                _values "mode" \$modes
                                ;;
                            *)
                                _values "label" \$(cdf -l)
                                ;;
                        esac
                        ;;
                    *)
                        local mode=\${words[2]}
                        case \$mode in
                            --)
                                _values "label" \$(cdf -l)
                                ;;
                            -a)
                                case \$CURRENT in
                                    3) _values "label" \$(cdf -l) ;;
                                    *) _path_files -/ ;;
                                esac
                                ;;
                            -g)
                                _values "label" \$(cdf -l)
                                ;;
                            -l)
                                ;;
                            -r)
                                _values "label" \$(cdf -l)
                                ;;
                            -w)
                                _values "type" @$supported_shells
                                ;;
                            -h)
                                ;;
                        esac
                        ;;
                esac
            }
            compdef _cdf cdf
            EOF
        } elsif ($type eq "yash") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            function cdf {
                if [ \$# -eq 0 ]; then
                    command -- cdf
                    return
                elif [ \$# -eq 1 ] && [ "\$1" = "--" ]; then
                    command -- cdf
                    return
                elif [ \$# -ge 1 ] && [ "\$1" != "\${1#-}" ] && [ "\$1" != "--" ]; then
                    command -- cdf "\$@"
                    return
                fi

                if [ "\$1" = "--" ]; then
                    shift
                fi

                set -- "\$(command -- cdf -g "\$1")"
                if [ -n "\$1" ]; then
                    cd "\$1" || return
                fi
            }

            function completion/cdf {
              CWORD=\${WORDS[#]}

              case \$CWORD in
                1)
                  case \$TARGETWORD in
                    -*) command -f completion/cdf::completecmd ;;
                    *)  command -f completion/cdf::completelabel ;;
                  esac
                  ;;
                *)
                  cmd=\${WORDS[2]}
                  case \$cmd in
                    --)
                      command -f completion/cdf::completelabel
                      ;;
                    -a)
                      case \$CWORD in
                        2) command -f completion/cdf::completelabel ;;
                        *) complete -d ;;
                      esac
                      ;;
                    -g)
                      command -f completion/cdf::completelabel
                      ;;
                    -l)
                      ;;
                    -r)
                      command -f completion/cdf::completelabel
                      ;;
                    -w)
                      command -f completion/cdf::completewrapper
                      ;;
                  esac
                  ;;
              esac
            }

            function completion/cdf::completecmd {
              complete -D "chdir to the path so labeled" -- --
              complete -D "save the path with the label" -- -a
              complete -D "get the path so labeled"      -- -g
              complete -D "list labels"                  -- -l
              complete -D "remove the label"             -- -r
              complete -D "output the wrapper script"    -- -w
              complete -D "print usage"                  -- -h
            }

            function completion/cdf::completelabel {
              complete -- \$(cdf -l)
            }

            function completion/cdf::completewrapper {
              complete -- @$supported_shells
            }
            EOF
        } elsif ($type eq "fish") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            function cdf
              if test (count \$argv) -eq 0
                command cdf
                return
              end
              if test (count \$argv) -eq 1; and test \$argv[1] = "--"
                command cdf
                return
              end
              if test (count \$argv) -ge 1; and string match -q -r "^-" -- \$argv[1]; and test \$argv[1] != "--"
                command cdf \$argv
                return
              end

              if test \$argv[1] = "--"
                set argv \$argv[2..-1]
              end

              set -l nextpath (command cdf -g \$argv[1])
              if test -n "\$nextpath"
                cd \$nextpath
              end
            end

            function __fish_cdf_complete
              set -l cur (commandline -tc)
              set -l words (commandline -pco)
              set -l cword (count \$words)
              switch \$cword
                case 1
                  switch \$cur
                    case "-*"
                      echo -es -- "--" "\\t" "Chdir to the path so labeled"
                      echo -es -- "-a" "\\t" "Save the path with the label"
                      echo -es -- "-g" "\\t" "Get the path so labeled"
                      echo -es -- "-l" "\\t" "List labels"
                      echo -es -- "-r" "\\t" "Remove the label"
                      echo -es -- "-w" "\\t" "Output the wrapper script"
                      echo -es -- "-h" "\\t" "Print usage"
                    case "*"
                      cdf -l | awk '{print \$0 "\\t" "Label"}'
                  end
                case "*"
                  set -l cmd \$words[2]
                  switch \$cmd
                    case "--"
                      cdf -l | awk '{print \$0 "\\t" "Label"}'
                    case "-a"
                      switch \$cword
                        case 2
                          cdf -l | awk '{print \$0 "\\t" "Label"}'
                        case 3
                          __fish_complete_directories \$cur
                      end
                    case "-g"
                      cdf -l | awk '{print \$0 "\\t" "Label"}'
                    case "-r"
                      cdf -l | awk '{print \$0 "\\t" "Label"}'
                    case "-w"
                      printf "%s\\n" @$supported_shells | awk '{print \$0 "\\t" "Shell"}'
                  end
              end
            end
            complete -c cdf -f -a "(__fish_cdf_complete)"
            EOF
        } elsif ($type eq "tcsh") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            alias cdf '\\\\
            set __cdfq='"'"''"'"'"'"'"'"'"'"''"'"';\\\\
            set __cdfargs=(\\!:*);\\\\
            set __cdfnextpath;\\\\
            eval '"'"'\\\\
            source /dev/stdin <<__BODY__\\\\
              if (\\\$#__cdfargs == 0) then\\\\
                command -- cdf\\\\
                exit\\\\
              endif\\\\
              if (\\\$#__cdfargs == 1 && \\\$__cdfargs[1]:q == "--") then\\\\
                command -- cdf\\\\
                exit\\\\
              endif\\\\
              if (\\\$#__cdfargs >= 1 && \\\$__cdfargs[1]:q =~ -* && \\\$__cdfargs[1]:q != "--") then\\\\
                command -- cdf \\\$__cdfargs:q\\\\
                exit\\\\
              endif\\\\
              \\\\
              if (\\\$__cdfargs[1]:q == "--") then\\\\
                shift __cdfargs\\\\
              endif\\\\
              \\\\
              command -- cdf -g \\\$__cdfargs[1]:q | sed \${__cdfq}s/\${__cdfq}"\${__cdfq}"\${__cdfq}/\${__cdfq}"\${__cdfq}"\${__cdfq}"\${__cdfq}"\${__cdfq}"\${__cdfq}"\${__cdfq}"\${__cdfq}"\${__cdfq}/g; s/\\\\\\\\\\!/\\\\\\\\\\\\\\\\\\!/g; s/\\\$/\\\\\\\\/; 1s/^/\${__cdfq}"\${__cdfq}"\${__cdfq}/; \\\$s/\\\\\\\\\\\$/\${__cdfq}"\${__cdfq}"\${__cdfq}/\${__cdfq} | sed \${__cdfq}1s/^/set __cdfnextpath=/\${__cdfq} | source /dev/stdin\\\\
              true\\\\
              if (\\\$__cdfnextpath:q != "") then\\\\
                cd \\\$__cdfnextpath:q\\\\
              endif\\\\
            __BODY__\\\\
            true\\\\
            '"'"';\\\\
            unset __cdfargs;\\\\
            unset __cdfnextpath;\\\\
            unset __cdfq;\\\\
            '

            alias __cdfcomplete '\\\\
            set __cdfcompleteargs=(\$COMMAND_LINE);\\\\
            set __cdfq='"'"''"'"'"'"'"'"'"'"''"'"';\\\\
            eval '"'"'\\\\
            source /dev/stdin <<__BODY__\\\\
              if (\\\$COMMAND_LINE:q =~ "* ") then\\\\
                set __cdfcompleteargs=(\\\$__cdfcompleteargs:q "")\\\\
              endif\\\\
              \\\\
              switch (\\\$#__cdfcompleteargs)\\\\
              case 2:\\\\
                switch (\\\$__cdfcompleteargs[2]:q)\\\\
                case "-*":\\\\
                  printf "%s\\n" -- -a -g -l -r -w -h\\\\
                  breaksw\\\\
                default:\\\\
                  command -- cdf -l\\\\
                  breaksw\\\\
                endsw\\\\
                breaksw\\\\
              default:\\\\
                switch (\\\$__cdfcompleteargs[2]:q)\\\\
                case "--":\\\\
                  command -- cdf -l\\\\
                  breaksw\\\\
                case "-a":\\\\
                  switch (\\\$#__cdfcompleteargs)\\\\
                  case 3:\\\\
                    command -- cdf -l\\\\
                    breaksw\\\\
                  default:\\\\
                    sh -c \${__cdfq}ls -dp -- "\\\$1"* 2> /dev/null\${__cdfq} -- \\\$__cdfcompleteargs[\\\$#__cdfcompleteargs]:q | awk \${__cdfq}/\\/\\\$/{print;print}\${__cdfq}\\\\
                    breaksw\\\\
                  endsw\\\\
                  breaksw\\\\
                case "-g":\\\\
                  command -- cdf -l\\\\
                  breaksw\\\\
                case "-r":\\\\
                  command -- cdf -l\\\\
                  breaksw\\\\
                case "-w":\\\\
                  printf "%s\\n" @$supported_shells\\\\
                  breaksw\\\\
                endsw\\\\
                breaksw\\\\
              endsw\\\\
            __BODY__\\\\
            true\\\\
            '"'"';\\\\
            unset __cdfcompleteargs;\\\\
            unset __cdfq;\\\\
            '
            complete cdf 'p/*/`__cdfcomplete`/'
            EOF
        } elsif ($type eq "rc") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            fn cdf {
              if ({~ \$#* 0} || {~ \$#* 1 && ~ \$1 '--'} || {test \$#* -ge 1 && ~ \$1 -* && ! ~ \$1 '--'}) {
                command -- cdf \$*
                return
              }

              if (~ \$1 '--') {
                shift
              }

              ifs='' nextpath=`{command -- cdf -g \$1 | awk 'NR==1{l=\$0;while(getline){print l;l=\$0};printf"%s",l}'} if (test -n \$nextpath) {
                cd \$nextpath
              }
            }
            EOF
        } elsif ($type eq "nyagos") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            nyagos.alias.cdf = function(args)
              if (#args == 0) or (#args == 1 and args[1] == "--") or (#args >= 1 and args[1]:match([[^-]]) and args[1] ~= "--") then
                nyagos.exec({"command", "--", "cdf", unpack(args)})
                return
              end

              if args[1] == "--" then
                table.remove(args, 1)
              end

              local label        = args[1]
              local quoted_label = label:gsub([[']], [['"'"']]):gsub([[^]], [[']]):gsub([[\$]], [[']])
              local next_path    = nyagos.eval("command -- cdf -g " .. quoted_label)
              if next_path ~= nil and next_path ~= "" then
                nyagos.chdir(next_path)
              end
            end
            nyagos.complete_for.cdf = function(args)
              local cur = args[#args]
              if #args == 2 then
                if cur:match([[^-]]) then
                  return nyagos.fields("-- -a -g -l -r -w -h")
                else
                  return nyagos.fields(nyagos.eval("command -- cdf -l"))
                end
              else
                local cmd = args[2]
                if cmd == "--" then
                  return nyagos.fields(nyagos.eval("command -- cdf -l"))
                elseif cmd == "-a" then
                  if #args == 3 then
                    return nyagos.fields(nyagos.eval("command -- cdf -l"))
                  else
                    return nil
                  end
                elseif cmd == "-g" then
                  return nyagos.fields(nyagos.eval("command -- cdf -l"))
                elseif cmd == "-l" then
                  return {}
                elseif cmd == "-r" then
                  return nyagos.fields(nyagos.eval("command -- cdf -l"))
                elseif cmd == "-w" then
                  return nyagos.fields("@$supported_shells")
                elseif cmd == "-h" then
                  return {}
                end
              end
            end
            EOF
        } elsif ($type eq "xonsh") {
            print <<"            EOF" =~ s/^ {12}//gmr;
            def __cdf(args):
                if (len(args) == 0) or (len(args) == 1 and args[0] == "--") or (len(args) >= 1 and args[0].startswith("-") and args[0] != "--"):
                    command -- cdf @(args)
                    return

                if (args[0] == "--"):
                    args.pop(0)

                nextpath = ''.join(!(command -- cdf -g @(args[0]))).strip()
                if nextpath != "":
                    cd @(nextpath)

            def __complete_cdf(prefix, line, start, end, ctx):
                """
                Completion for "cdf"
                """

                from xonsh.completers.path import complete_dir

                words = line[:end].split()
                if line.endswith(" "):
                    words.append("")

                raw_comps = []
                completed = False
                comps     = None
                lp        = None
                if start != 0 and words[0] == "cdf":
                    if len(words) == 2:
                        if prefix.startswith("-"):
                            raw_comps += ["--", "-a", "-g", "-l", "-r", "-w", "-h"]
                        else:
                            raw_comps += \$(command -- cdf -l).split()
                    else:
                        if words[1] == "--":
                            raw_comps += \$(command -- cdf -l).split()
                        elif words[1] == "-a":
                            if len(words) == 3:
                                raw_comps += \$(command -- cdf -l).split()
                            else:
                                comps, lp = complete_dir(prefix, line, start, end, ctx, True)
                                completed = True
                        elif words[1] == "-g":
                            raw_comps += \$(command -- cdf -l).split()
                        elif words[1] == "-r":
                            raw_comps += \$(command -- cdf -l).split()
                        elif words[1] == "-w":
                            raw_comps += [@{[join ", ", map { "\"$_\"" } @$supported_shells]}]

                if completed:
                    return comps, lp
                else:
                    comps = set(filter(lambda s: s.startswith(prefix), raw_comps))
                    if (len(comps) == 1):
                        comps = set(map(lambda s: s + " ", comps))
                    lp = len(prefix)
                    return comps, lp

            aliases["cdf"] = __cdf

            if \$(completer list).find('cdf : Completion for "cdf"') == -1:
                completer add cdf __complete_cdf
            EOF
        } else {
            print STDERR "$cmd_name: $mode: $type doesn't supported\n";
            exit 2;
        }

    } elsif ($mode eq "-h") {

        print $usage;

    } else {

        print STDERR "$cmd_name: unrecognized command '$mode'\n";
        print STDERR "Try '$cmd_name -h' for more information.\n";
        exit 2;

    }
}

main;
