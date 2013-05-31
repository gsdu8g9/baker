# convert string to hook
slug() {
    tr -d [:cntrl:][:punct:] | tr -s [:space:] - | tr -s [:upper:] [:lower:] <<< "$*"
}

# get meta from file heading
# $1: file
# $2: key
header() {
    grep -m 1 -o "^$2: .\+" "$1" | cut -f 2- -d " "
}

# get content of the file
# $1: file
body() {
    grep -q "^---$" "$1" && sed "1,/^---$/d" "$1" || cat "$1"
}

# get include tag's template name
# $1: file
listIncludeName() {
    grep -o "{% include [a-z]\+ %}" <<<"$1" | sed "s/{% include \([a-z]\+\) %}/\1/g" | sort -u
}

# get tag offset and tag
# $1: template string
listStartEndControlTag() {
    grep -oba "{% \(foreach .\+\|if .\+\|endif\|endforeach\) %}" <<<"$1"
}

# check if the tag is start tag
# $1: template string
isStartTag() {
    grep -q "^{% \(foreach .\+\|if .\+\) %}$" <<<"$1"
}

# get tag name from tag
# $1: tag
tagName() {
    sed "s/^{% \([a-z]\+\) .*$/\1/" <<<"$1"
}

# get tag context from tag
# $1: tag
tagContext() {
    sed "s/^{% [a-z]\+ \(.*\) %}$/\1/" <<<"$1"
}

# get end tag from start tag
# $1: start tag
endTagOf() {
    grep -q "^{% foreach .\+ %}$" <<<"$1" && echo "{% endforeach %}"
    grep -q "^{% if .\+ %}$" <<<"$1" && echo "{% endif %}"
}

stackPush() {
    stack=("${stack[@]}" "$1")
}

stackPop() {
    local i=$(( ${#stack[@]} - 1 ))
    (( $i < 0 )) && return
    unset stack[$i]
}

stackPeek() {
    local i=$(( ${#stack[@]} - 1 ))
    (( $i < 0 )) && return
    echo "${stack[$i]}"
}

# match end tag
checkTag() {
    local IFS=$'\n'
    local stack=()
    local startOffset=0
    local startTag=""
    local instance
    for instance in $(listStartEndControlTag "$1"); do
        local offset="$(cut -d : -f 1 <<< "$instance")"
        local tag="$(cut -d : -f 2 <<< "$instance")"

        if isStartTag "$tag"; then
            if [[ "${#stack[@]}" == 0 ]]; then
                startOffset="$offset"
                startTag="$tag"
            fi
            stackPush "$tag"
        else
            endTag="$(endTagOf "$(stackPeek)")"
            stackPop
            [[ "$endTag" != "$tag" ]] && return
            [[ "${#stack[@]}" == 0 ]] && echo "$startTag:$((startOffset + ${#startTag} )):$(( $offset - $startOffset - ${#startTag} ))"
        fi
    done
}

# $1: tag
# $2: content
# $3: context
doForeach() {
    local context="$(tagContext "$1")"
    eval "declare -A vars=${3#*=}"
    #echo "$1"
    local i=0
    while [[ "${vars[${context}.${i}]}" ]]; do
        local thisContext="${vars[${context}.${i}]}"
        #echo "run $i times"
        eval "declare -A subvars=${thisContext#*=}"
        local j
        for j in "${!subvars[@]}"; do
            vars[${context}.${j}]="${subvars[$j]}"
        done
        doTag "$2" "$(declare -p vars)"
        (( i++ ))
    done
}


# $1: tag
# $2: content
# $3: context
doIf() {
    local context="$(tagContext "$1")"
    eval "declare -A vars=${3#*=}"
    if [[ "$context" =~ ^! ]]; then
        context="${context##*!}"
        [[ "vars[$context]" == true ]] || doTag "$2" "$3"
    else
        [[ "vars[$context]" == true ]] && doTag "$2" "$3"
    fi
}

# $1: template string
# $2: context
doTag() {
    local IFS=$'\n'
    local lastStartOffset=0
    local instance
    for instance in $(checkTag "$1"); do
        #echo "$instance"
        local tag="$(cut -d : -f 1 <<< "$instance")"
        local endTag="$(endTagOf "$tag")"
        local tagName="$(tagName "$tag")"
        local start="$(cut -d : -f 2 <<< "$instance")"
        local length="$(cut -d : -f 3 <<< "$instance")"
        doReplacement "${1:$lastStartOffset:$(( $start - ${#tag} - $lastStartOffset ))}" "$2"
        if [[ "$tagName" == foreach ]]; then
            doForeach "$tag" "${1:$start:$length}" "$2"
        elif [[ "$tagName" == if ]]; then
            doIf "$tag" "${1:$start:$length}" "$2"
        fi
        lastStartOffset="$(( $start + $length + ${#endTag} ))"
    done
    doReplacement "${1:$lastStartOffset}" "$2"
}

# replace {% include %} and {{ var }}
# $1: template string
# $2: context
doReplacement() {
    eval "declare -A vars=${2#*=}"
    local result="$1"
    # {{ var }}
    local i
    for i in "${!vars[@]}"; do
        local from="{{ $i }}"
        local to="${vars[$i]}"
        result="${result//$from/$to}"
    done

    # {% include %}
    for i in $(listIncludeName "$1"); do
        local from="{% include $i %}"
        local to="$(doInclude "$i" "$2")"
        result="${result//$from/$to}"
    done
    echo -n "$result"
}


# $1: file name
# $2: context
doTemplate() {
    local layout="$(header "$1" layout)"
    # next level for layout
    local result="$(doTag "$(body "$1")" "$2")"
    if [[ -z "$layout" ]]; then
        echo "$result"
    else
        eval "declare -A vars=${2#*=}"
        vars[content]="$result"
        doLayout "$layout" "$(declare -p vars)"
    fi
}

# $1: include layout name
# $2: context
doInclude() {
    local includes="$THEME_DIR/$INCLUDE_DIR/$1$INCLUDE_EXT"
    if [[ ! -f "$includes" ]]; then
        echo "include not found: $includes"
    fi
    doTemplate "$includes" "$2"
}

# process layout
# $1: layout name
# $2: context
doLayout() {
    local layouts="$THEME_DIR/$LAYOUT_DIR/$1$LAYOUT_EXT"
    if [[ ! -f "$layouts" ]]; then
        echo "layout not found: $layouts"
    fi
    doTemplate "$layouts" "$2"
}