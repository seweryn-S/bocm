#!/bin/bash
#set -E -o functrace
set -E
# declare -a func_stack

function handle_exception() {
    local _lineno="${1:-LINENO}"
    local _bash_lineno="${2:-BASH_LINENO}"
    local _last_code_line="${3}"
    local _last_command="${4}"
    local _code="${5}"

    local -a _output_array=()

    _output_array+=(
        "*** Exception ***"
        "  "
        "   Source line: ${_last_code_line}"
        "       Command: ${_last_command}"
        "   Line number: $_lineno"
        "Function_trace: [${FUNCNAME[*]:1}] ${BASH_LINENO[1]}"
        "     Exit code: ${_code}"
        "  "
        "***************"
    )
    # echo "  Function call stack:"
    # for i in "${func_stack[@]}"; do
    #     echo "  $i"
    # done

    printf '%s\n' "${_output_array[@]}" >&2

    [[ $(type -t panic) == function ]] && panic || exit ${_code}
}

trap 'handle_exception "${LINENO}" "${BASH_LINENO}" "${BASH_COMMAND}" "$(eval echo ${BASH_COMMAND})" "${?}"' ERR

# function push_func() {
#     local func_info="${FUNCNAME[1]} line number ${BASH_LINENO[0]}"
#     func_stack+=("${func_info}")
# }

# function pop_func() {
#     unset 'func_stack[-1]'
# }

ZMIENNA="tresc_zmienna"

_funcPierwsza() {
    # push_func
    local ZMIENNA1="tresc_zmienna_1"

    # echo ${1} ${2} ${ZMIENNA1}
    ls /sew ${1} ${2} ${ZMIANNA1}
    # pop_func
}

_funcDruga() {
    # push_func
    local ZMIENNA2="tresc_zmienna_2"

    
    _funcPierwsza ${1} ${ZMIENNA2}
    # pop_func
}

_funcDruga ${ZMIENNA}