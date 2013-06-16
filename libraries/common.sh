headline() {
    tput setaf 4
    echo -n " :: "
    tput sgr0
    echo "$*"
}

debug() {
    echo "$*" 1>> baker-error.log
}

# convert string to hook
slug() {
    tr -d [:cntrl:][:punct:] <<< "$*" | tr -s [:space:] - | tr [:upper:] [:lower:]
}

# $@: variable strings
toString() {
    declare -A _var
    local arg
    for arg in "$@"; do
        eval "declare -A _var2=${arg#*=}" 2>/dev/null || eval "declare -A _var2=$arg"
        local i
        for i in "${!_var2[@]}"; do
            _var[$i]="${_var2[$i]}"
        done
    done
    declare -p _var | clean
}

# $1: variable name, declared
toArray() {
    eval "declare -A _var=$(toString "${@:2}")"
    local i
    for i in "${!_var[@]}"; do
        eval "${1}[$i]=${_var[$i]}"
    done
}

# strip declare
clean() {
    local str="$(cat -)"
    echo "${str#*=}"
}

# $1: variable name, declared
# $2: append index
# $3: append value
appendTo() {
    eval "declare -A _var=$1"
    _var[$2]="$3"
    declare -p _var | clean
}