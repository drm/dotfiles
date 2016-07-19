##
# Helper function to print a color escape code within a prompt.
##
function ps_color {
    local color=$1
    echo "\[\e[${color}m\]"
}


##
# Renders the prompt, as follows:
# If in a git working tree:
# 
#   project_dir/relative_path: [num_changes/num_staged] branch ([+num_ahead]-[num_behind]) $ 
#
#   - `project_dir`: the basename of the directory the `.git` folder is in (i.e. the root of the project)
#   - `relative_path`: the path relative to the root of the git project
#   - `num_changes`: The number of changes that are not staged yet
#   - `num_staged`: The number of changes that are staged
#   - `branch-name`: The branch the working tree is currently on.
#   - `num_ahead`: The number of commits that were not yet merged with the remote (i.e.: not yet pushed)
#   - `num_behind`: The number of commits that are not yet merged with the local (i.e.: not yet pulled)
# 
# If the branch is clean (i.e., no uncommitted or unstaged changes), a checkmark is shown before the branch name
# If the checkout is detached, a red `detached` message is shown
# If not in a git working tree, the working dir is printed in stead of all the git info
#
# Examples:
# Assuming we're in the 'src' folder of a clean project, checked out in `~/projects/foo`:
#  
#   foo/src: master $ _
#
# Assuming we're in the 'src' folder of a project, in a branch called 'hotfix/bar', 
# 3 commits ahead of origin, with 1 unstaged and 3 uncommitted files:
#
#   foo/src: 3/1 master (+2) $ _
##
function render_prompt {
    local branch
    local remote
    local gitroot
    local rootname
    local wd
    local status
    local num_changed
    local num_staged
    local num_ahead
    local num_behind
    local ps1

    if branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null); then
        gitroot=$(git rev-parse --show-toplevel)
        rootname="$(basename $gitroot)"
        rel=$(python -c "import os.path; print os.path.relpath('"$(pwd)"', '"$gitroot"')")
        if [[ "$rel" == "." ]]; then 
            wd="$rootname"
        else
            wd="$rootname/$rel"
        fi

        if git clean -xnd `pwd` | grep 'Would remove \./' > /dev/null; then
            ps1="$ps1$(ps_color 33)$rootname/(!$(ps_color "1;31")$rel$(ps_color "0;33"))"
        else
            ps1="$ps1$(ps_color 33)$wd: "
        fi

        status=$(git status --porcelain)
        num_changed=$(git status --porcelain | egrep -v '^[AMDR]' | wc -l)
        num_staged=$(git status --porcelain | egrep '^[AMDR]' | wc -l)

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
render_prompt

