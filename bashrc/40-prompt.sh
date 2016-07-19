function ps_color {
    local color=$1
    echo "\[\e[${color}m\]"
}

function render_prompt {
    local branch
    local remote
    local gitroot
    local wd
    local status
    local num_changed
    local num_staged
    local num_ahead
    local num_behind
    local ps1

    if branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null); then
        gitroot=$(git rev-parse --show-toplevel)
        wd="$(basename $gitroot)"
        rel=$(python -c "import os.path; print os.path.relpath('"$(pwd)"', '"$gitroot"')")
        if [[ "$rel" != "." ]]; then 
            wd="$wd/$rel"
        fi
        ps1="$ps1$(ps_color 33)$wd: "

        status=$(git status --porcelain)
        num_changed=$(git status --porcelain | egrep -v '^[AMD]' | wc -l)
        num_staged=$(git status --porcelain | egrep '^[AMD]' | wc -l)

        if remote=$(git config branch.${branch}.remote); then
            tracking_branch="${remote}/${branch}"
            num_ahead=$(git rev-list "${tracking_branch}..${branch}" --count)
            num_behind=$(git rev-list "${branch}..${tracking_branch}" --count)
        fi

        if [[ "$branch" == "HEAD" ]]; then
            ps1="$ps1$(ps_color "1;31")detached"
        elif [[ "$status" == "" ]]; then
            ps1="$ps1$(ps_color "1;32")✓ $branch$(ps_color 0)"
        else
            ps1="$ps1$(ps_color "1;33")${num_changed}$(ps_color 0)/$(ps_color "1;32")${num_staged} $(ps_color 36)$branch$(ps_color 0)"
        fi
        if [[ "$num_ahead" -gt 0 ]]; then
            ps1="$ps1(+${num_ahead})";
        fi
        if [[ "$num_behind" -gt 0 ]]; then
            ps1="$ps1(-${num_behind})";
        fi
    else
        ps1="$ps1$(ps_color 33)\w"
    fi

    export PS1="$ps1 $(ps_color 0)$ "
}

PROMPT_COMMAND="render_prompt; $PROMPT_COMMAND"
PSCOLOR=32

render_prompt

