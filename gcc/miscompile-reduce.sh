#!/usr/bin/env bash
# Script used w/ cvise for https://gcc.gnu.org/PR113734 to reduce a miscompilation
# TODO:
# * Factor out the options needed to trigger a crash
# * Move the exit code conditions into variables (e.g. should Valgrind crash on it?)
# * Add MSAN variable? (Check if clang is in COMPILERS, maybe?)
# * Add general flags var which is added for all commands, not just w/ optimisation
# * Move timeout into var
# * Maybe have an assoc. array of cases which should fail/pass?

set -x

ulimit -c 0

# Used for tests where we check for miscompilation, also to add to compiler list for baseline (to make sure it passes sometimes)
BAD_COMPILER="gcc-14"

# Compilers to test each combination with
#COMPILERS=( gcc-13 clang )
COMPILERS=( gcc-11 gcc-12 gcc-13 clang )

# Range of optimisations to check with
#OPTS=( -O2 -O3 )
OPTS=( -O0 -O1 -O2 -O3 )

# -mcpu=native, -march=znver2, etc
ISA=( '' -march=znver2 )

# Safeguards against bad reductions
ERROR_OPTIONS=( -Werror=return-type -Werror=uninitialized -Werror=overflow -Werror=sequence-point )

# Should we check with Valgrind? Disable if CPU isn't supported
VALGRIND=${VALGRIND:=1}

##

export ASAN_OPTIONS="halt_on_error=1:abort_on_error=1:print_summary=1"
export UBSAN_OPTIONS="halt_on_error=1:abort_on_error=1:print_summary=1:print_stacktrace=1"
export MSAN_OPTIONS="halt_on_error=1:abort_on_error=1:print_summary=1:print_stacktrace=1"

# With vectorisation, we want it to abort.
for abi in '' '-m32' ; do
    "${BAD_COMPILER}" test.c -o test "${ERROR_OPTIONS[@]}" -O3 -march=znver2 ${abi} || exit 1

    timeout 20s ./test
    timeout_result=$?
    case ${timeout_result} in
        124)
            # Timed out
            exit 1
            ;;
        0)
            # It succeeded which is not what we wanted.
            exit 1
            ;;
        *)
            # Crashed, yay!
            ;;
    esac
done

# It should work:
# * without vectorisation, or
# * with clang.
for compiler in "${COMPILERS[@]}" "${BAD_COMPILERS[@]}"; do
    for opt in "${OPTS[@]}" ; do
        # Only add the error options for sufficient optimisation, otherwise
        # e.g. -Wmaybe-unitialized has FPs.
        case ${opt} in
            *O2*|*O3*)
                opt+=" ${ERROR_OPTIONS[@]}"
                ;;
            *)
                ;;
        esac

        ${compiler} test.c -o test ${opt} || exit 1
        timeout 20s ./test
        timeout_result=$?
        case ${timeout_result} in
            124)
                # Timed out
                exit 1
                ;;
            0)
                ;;
            *)
                # Crashed
                exit 1
                ;;
        esac
    done
done

# We want sanitizers to be happy with both GCC and Clang.
for compiler in "${COMPILERS[@]}" "${BAD_COMPILERS[@]}" ; do
    for opt in "${OPTS[@]}" ; do
        for sanitizer in '-fsanitize=address,undefined' ; do
            # Only add the error options for sufficient optimisation, otherwise
            # e.g. -Wmaybe-unitialized has FPs.
            case ${opt} in
                *O2*|*O3*)
                    opt+=" ${ERROR_OPTIONS[@]}"
                    ;;
                *)
                    ;;
            esac

            ${compiler} test.c -o test ${opt} ${sanitizer} || exit 1
            timeout 20s ./test
            timeout_result=$?
            case ${timeout_result} in
                124)
                    # Timed out
                    exit 1
                    ;;
                0)
                    ;;
                *)
                    # Crashed
                    exit 1
                    ;;
            esac

        done
    done
done

# Test vectorisation with older GCC, Clang, and sanitizers. We want it to pass here.
for compiler in "${COMPILERS[@]}"  ; do
    for opt in "${OPTS[@]}" ; do
        for abi in '' '-m32' ; do
            for sanitizer in '' '-fsanitize=address,undefined' ; do
                # Don't use -Werror with sanitizers as it's unreliable.
                if [[ -z ${sanitizer} ]] ; then
                    # Only add the error options for sufficient optimisation, otherwise
                    # e.g. -Wmaybe-unitialized has FPs.
                    case ${opt} in
                        *O2*|*O3*)
                            opt+=" ${ERROR_OPTIONS[@]}"
                            ;;
                        *)
                            ;;
                    esac
                fi

                ${compiler} test.c -o test -march=znver2 ${abi} ${opt} ${sanitizer} || exit 1
                timeout 20s ./test
                timeout_result=$?
                case ${timeout_result} in
                    124)
                        # Timed out
                        exit 1
                        ;;
                    0)
                        ;;
                    *)
                        # Crashed
                        exit 1
                        ;;
                esac
            done
        done
    done
done

# We want to avoid real uninitialised use (=> we want it to still fail with some trivial init).
"${BAD_COMPILER}" test.c -o test "${ERROR_OPTIONS[@]}" -O3 -march=znver2 -ftrivial-auto-var-init=zero || exit 1
timeout 20s ./test
timeout_result=$?
case ${timeout_result} in
    124)
        # Timed out
        exit 1
        ;;
    0)
        # It succeeded which is not what we wanted.
        exit 1
        ;;
    *)
        # Crashed, yay!
        ;;
esac

# We also want Clang's MSAN to be happy.
for opt in "${OPTS[@]}" ; do
    for march in "${ISA[@]}" ; do
        clang test.c -o test -fsanitize=memory ${march} ${opt} || exit 1
        timeout 20s ./test
        timeout_result=$?
        case ${timeout_result} in
            124)
                # Timed out
                exit 1
                ;;
            0)
                ;;
            *)
                # Crashed
                exit 1
                ;;
        esac
    done
done

if [[ -n ${VALGRIND} && ${VALGRIND} == 1 ]] ; then
    # (We do these two Valgrind tests before the loop Valgrind below deliberately)

    # With vectorisation, we want to get a (bogus) uninitialised read, so Valgrind has to fail.
    "${BAD_COMPILER}" test.c -o test "${ERROR_OPTIONS[@]}" -O3 -march=znver2 || exit 1
    # no non-valgrind exec check here as we already did it at the beginning
    valgrind -q --vgdb=no --leak-check=no --error-exitcode=2 --exit-on-first-error=yes ./test
    ret=$?
    if [[ ${ret} != 2 ]] ; then
        # This is a bad reduction if Valgrind thought it was OK.
        exit 1
    fi

    # We don't want it to rely on aliasing violations.
    "${BAD_COMPILER}" test.c -o test "${ERROR_OPTIONS[@]}" -O3 -march=znver2 -fno-strict-aliasing || exit 1
    timeout 20s ./test
    timeout_result=$?
    case ${timeout_result} in
        124)
            # Timed out
            exit 1
            ;;
        0)
            # It succeeded which is not what we wanted.
            exit 1
            ;;
        *)
            # Crashed, yay!
            ;;
    esac

    valgrind -q --vgdb=no --leak-check=no --error-exitcode=2 --exit-on-first-error=yes ./test
    ret=$?
    if [[ ${ret} != 2 ]] ; then
        # This is a bad reduction if Valgrind thought it was OK.
        exit 1
    fi

    # We want Valgrind to be happy with both older GCC and Clang with vectorisation.
    for compiler in "${COMPILERS[@]}" ; do
        for opt in "${OPTS[@]}" ; do
            for march in "${ISA[@]}" ; do
                # Only add the error options for sufficient optimisation, otherwise
                # e.g. -Wmaybe-uninitialized has FPs.
                case ${opt} in
                    *O2*|*O3*)
                        opt+=" ${ERROR_OPTIONS[@]}"
                        ;;
                    *)
                        ;;
                esac

                ${compiler} test.c -o test ${march} ${opt} || exit 1
                # Do a quick cheap test w/o Valgrind first as it's expensive.
                timeout 20s ./test
                timeout_result=$?
                case ${timeout_result} in
                    124)
                        # Timed out
                        exit 1
                        ;;
                    0)
                        ;;
                    *)
                        # Crashed
                        exit 1
                        ;;
                esac

                valgrind -q --vgdb=no --leak-check=no --error-exitcode=2 --exit-on-first-error=yes ./test
                ret=$?

                if [[ ${ret} != 0 ]] ; then
                    exit 1
                fi
            done
        done
    done
fi

exit 0
