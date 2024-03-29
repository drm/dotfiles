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
#   foo/src: ✓ master $ _
#
# Assuming we're in the 'src' folder of a project, in a branch called 'hotfix/bar', 
# 2 commits ahead of origin, with 1 unstaged and 3 uncommitted files:
#
#   foo/src: 3/1 hotfix/bar (+2) $ _
#
# Assuming we're in a vendor dir of a project, where the vendor dir itself is not a git
# checkout, but ignored from git:
#
#   foo/vendor/symfony/symfony: master $ _
#       ^^^^^^^^^^^^^^^^^^^^^^
#       This part will be in a red color
##
function render_prompt {
    local branch
    local remote
    local gitroot
    local rootname
    local status
    local num_changed
    local num_staged
    local num_ahead
    local num_behind
    local ps1
    local parent_proc

    ps1=""

    parent_proc="$(ps -o command= $PPID)"
    case $parent_proc in
	    vim)
		    ps1="$(ps_color "1;30")($parent_proc) $(ps_color "1;0")"
	    ;;
    esac

    if gitroot=$(git rev-parse --show-toplevel 2>/dev/null); then
        if ( cd $gitroot/../ && git rev-parse 2>/dev/null); then
            ps1="$(ps_color "1;0")$(basename $(cd $gitroot/../ && git rev-parse --show-toplevel 2>/dev/null))$(ps_color "1;30")/.../$(ps_color "1;0")"
        fi

        rootname="$(basename $gitroot)"
        rel=$(python -c "import os.path; print os.path.relpath('"$(pwd)"', '"$gitroot"')")
        if [[ "$rel" == "." ]]; then 
            rel="/"
        fi

        ps1="$ps1$rootname"
        ps1="$ps1$(ps_color "0;33"): " 

        declare $(git status --porcelain | \
                 awk 'BEGIN { num_changed=0; num_staged=0; num_unknown=0; FS="\n"} 
                 { if ($1 ~ /^[AMDR]/) num_staged++; else if ($1 ~ /^\?/) num_unknown++; else num_changed++; } 
                 END { print "num_changed="num_changed" num_staged="num_staged" num_unknown="num_unknown }'; \
        )

        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); 
        if remote=$(git config branch.${branch}.remote); then
            tracking_branch="${remote}/${branch}"
            num_ahead=$(git rev-list "${tracking_branch}..${branch}" --count 2>/dev/null)
            num_behind=$(git rev-list "${branch}..${tracking_branch}" --count 2>/dev/null)
        fi
        if [[ "$branch" == "HEAD" ]]; then
            branch="detached"
            branch_color="1;31";
        elif [[ $num_staged -gt 0 ]] || [[ $num_changed -gt 0 ]] || [[ $num_unknown -gt 0 ]]; then
            ps1="$ps1$(ps_color "1;32")${num_staged}$(ps_color 0)/$(ps_color "1;33")${num_changed}$(ps_color 0)/$(ps_color "1;31")${num_unknown}$(ps_color 0) "
            branch_color="1;36";
        else
            ps1="$ps1$(ps_color "1;32")✓ ";
            branch_color="1;32"
        fi;
        ps1="$ps1$(ps_color "$branch_color")$branch$(ps_color 0) "
        if [[ "$num_ahead" -gt 0 ]]; then
            ps1="$ps1(+${num_ahead}) ";
        fi
        if [[ "$num_behind" -gt 0 ]]; then
            ps1="$ps1(-${num_behind}) ";
        fi
        
        if [[ "$(git ls-files)" == "" ]]; then
            ps1="$ps1$(ps_color "1;31")$rel"
        else
            ps1="$ps1$(ps_color "1;30")$rel"
        fi
    else
        ps1="$ps1$(ps_color 0)\w"
    fi

    export PS1="$ps1 $(ps_color 0)$ "
}

if ! [[ "$PROMPT_COMMAND" =~ "render_prompt;" ]]; then
    PROMPT_COMMAND="render_prompt; $PROMPT_COMMAND"
fi
render_prompt

