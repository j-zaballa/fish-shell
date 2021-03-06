# Interactive tests using `expect`
#
# There is no shebang line because you shouldn't be running this by hand. You
# should be running it via `make test` to ensure the environment is properly
# setup.

if test "$TRAVIS_OS_NAME" = osx
    echo "Skipping interactive tests on macOS on Travis"
    exit 0
end

# Set this var to modify behavior of the code being tests. Such as avoiding running
# `fish_update_completions` when running tests.
set -gx FISH_UNIT_TESTS_RUNNING 1

# Change to directory containing this script
cd (dirname (status -f))

# These env vars should not be inherited from the user environment because they can affect the
# behavior of the tests. So either remove them or set them to a known value.
# See also tests/test.fish.
set -gx TERM xterm
set -e ITERM_PROFILE

# Test files specified on commandline, or all *.expect files.
if set -q argv[1]
    set expect_files_to_test $argv.expect
    set pexpect_files_to_test pexpects/$argv.py
else
    set expect_files_to_test *.expect
    set pexpect_files_to_test pexpects/*.py
end

source test_util.fish (status -f) $argv
or exit
cat interactive.config >>$XDG_CONFIG_HOME/fish/config.fish

say -o cyan "Testing interactive functionality"
function test_expect_file
    return
    set -l file $argv[1]
    echo -n "Testing file $file ... "
    set starttime (timestamp)
    begin
        set -lx TERM dumb
        expect -n -c 'source interactive.expect.rc' -f $file >$file.tmp.out 2>$file.tmp.err
    end
    set -l exit_status $status
    set -l res ok
    set test_duration (delta $starttime)
    mv -f interactive.tmp.log $file.tmp.log

    diff $file.tmp.out $file.out >/dev/null
    set -l out_status $status
    diff $file.tmp.err $file.err >/dev/null
    set -l err_status $status

    if test $out_status -eq 0 -a $err_status -eq 0 -a $exit_status -eq 0
        printf '%s\n' (set_color green)ok(set_color normal)" ($test_duration $unit)"
        # clean up tmp files
        rm -f $file.tmp.{err,out,log}
        return 0
    else
        say red fail
        if test $out_status -ne 0
            say yellow "Output differs for file $file. Diff follows:"
            colordiff -u $file.out $file.tmp.out
        end
        if test $err_status -ne 0
            say yellow "Error output differs for file $file. Diff follows:"
            colordiff -u $file.err $file.tmp.err
        end
        if test $exit_status -ne 0
            say yellow "Exit status differs for file $file."
            echo "Unexpected test exit status $exit_status."
        end
        if set -q SHOW_INTERACTIVE_LOG
            # dump the interactive log
            # primarily for use in travis where we can't check it manually
            say yellow "Log for file $file:"
            cat $file.tmp.log
        end
        return 1
    end
end

function test_pexpect_file
    set -l file $argv[1]
    echo -n "Testing file $file ... "

    begin
        set starttime (timestamp)
        set -lx TERM dumb

        # Help the script find the pexpect_helper module in our parent directory.
        set -lx --prepend PYTHONPATH (realpath $PWD/..)
        set -lx fish ../test/root/bin/fish
        set -lx fish_key_reader ../test/root/bin/fish_key_reader
        set -lx fish_test_helper ../test/root/bin/fish_test_helper

        # Note we require Python3.
        python3 $file
    end

    set -l exit_status $status
    if test "$exit_status" -eq 0
        set test_duration (delta $starttime)
        say green "ok ($test_duration $unit)"
    end
    return $exit_status
end

set failed

if not python3 -c 'import pexpect'
    say red "pexpect tests disabled: `python3 -c 'import pexpect'` failed"
    set pexpect_files_to_test
end
for i in $pexpect_files_to_test
    if not test_pexpect_file $i
        set failed $failed $i
    end
end

if not type -q expect
    say red "expect tests disabled: `expect` not found"
    set expect_files_to_test
end
for i in $expect_files_to_test
    if not test_expect_file $i
        say -o cyan "Rerunning test $i"
        rm -f $i.tmp.*
        if not test_expect_file $i
            set failed $failed $i
        end
    end
end

set failed (count $failed)
if test $failed -eq 0
    say green "All interactive tests completed successfully"
    exit 0
else
    set plural (test $failed -eq 1; or echo s)
    say red "$failed test$plural failed"
    exit 1
end
