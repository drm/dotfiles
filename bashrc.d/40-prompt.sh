##
# Renders the prompt, as follows:
# If in a git working tree:
#
#   project_dir/relative_path: [num_staged/num_changed/num_untracked] branch ([+num_ahead]-[num_behind]) $
#
#   - `project_dir`: the basename of the directory the `.git` folder is in
#   - `relative_path`: the path relative to the root of the git project
#   - `num_staged`: changes staged for commit (X column of porcelain)
#   - `num_changed`: changes in the working tree (Y column of porcelain)
#   - `num_untracked`: untracked files
#   - `branch`: current branch, or "detached" in red if HEAD is detached
#   - `num_ahead`/`num_behind`: commits ahead/behind upstream tracking branch
#
# If the working tree is clean a checkmark is shown before the branch name.
# If the current directory is ignored by git (e.g. a vendor/ subdir), the
# relative path is colored red.
# If gitroot's parent is itself inside another git repo (nested checkout),
# the outer project name is shown as a "outer/..." prefix.
# If the parent process is vim, "(vim)" is prefixed.
##

# Precomputed escape codes. Plain assignments so re-sourcing ~/.bashrc is safe.
_PC_RESET=$'\[\e[0m\]'
_PC_BOLD=$'\[\e[1;0m\]'
_PC_DIM=$'\[\e[1;30m\]'
_PC_GREEN=$'\[\e[1;32m\]'
_PC_YELLOW=$'\[\e[1;33m\]'
_PC_RED=$'\[\e[1;31m\]'
_PC_CYAN=$'\[\e[1;36m\]'
_PC_PATH=$'\[\e[0;33m\]'

function render_prompt {
    local ps1=""
    local gitroot rel rootname branch upstream ab outer_root pname line porcelain
    local ahead=0 behind=0 staged=0 changed=0 untracked=0
    local branch_color xy

    # Parent process prefix (vim/nvim/etc.) — read /proc/$PPID/comm,
    # no fork of `ps`. `comm` is just the executable name (no args), so the
    # case matches reliably even when the editor was launched with arguments.
    if [[ -r /proc/$PPID/comm ]]; then
        IFS= read -r pname < /proc/$PPID/comm
        case $pname in
            vim|nvim|vi|view)
                ps1+="${_PC_DIM}(${pname}) ${_PC_BOLD}"
                ;;
        esac
    fi

    # Gather branch + ahead/behind + per-file status in a single git call.
    # porcelain=v2 emits machine-readable "# branch.*" header lines plus one
    # line per changed/untracked/unmerged file.
    if porcelain=$(git status --porcelain=v2 --branch 2>/dev/null); then
        while IFS= read -r line; do
            case $line in
                '# branch.head '*)
                    branch=${line#'# branch.head '}
                    ;;
                '# branch.upstream '*)
                    upstream=${line#'# branch.upstream '}
                    ;;
                '# branch.ab '*)
                    ab=${line#'# branch.ab '}      # "+N -M"
                    ahead=${ab%% *}; ahead=${ahead#+}
                    behind=${ab##* };  behind=${behind#-}
                    ;;
                '1 '*|'2 '*)
                    # "1 XY ..." / "2 XY ..." — index (X) + worktree (Y) status.
                    # A file modified-and-restaged counts as both staged AND
                    # changed; the previous awk script only looked at X.
                    xy=${line:2:2}
                    [[ ${xy:0:1} != '.' ]] && (( staged++ ))
                    [[ ${xy:1:1} != '.' ]] && (( changed++ ))
                    ;;
                'u '*)
                    (( changed++ ))
                    ;;
                '? '*)
                    (( untracked++ ))
                    ;;
            esac
        done <<<"$porcelain"

        gitroot=$(git rev-parse --show-toplevel 2>/dev/null)
        rootname=${gitroot##*/}

        # Nested checkout: is gitroot itself inside another working tree?
        if outer_root=$(git -C "$gitroot/.." rev-parse --show-toplevel 2>/dev/null); then
            ps1+="${_PC_BOLD}${outer_root##*/}${_PC_DIM}/.../${_PC_BOLD}"
        fi

        # Relative path via bash parameter expansion — no python.
        rel=${PWD#"$gitroot"}
        rel=${rel#/}
        [[ -z $rel ]] && rel="/"

        ps1+="${rootname}${_PC_PATH}: "

        if [[ $branch == '(detached)' ]]; then
            branch="detached"
            branch_color=$_PC_RED
        elif (( staged + changed + untracked > 0 )); then
            ps1+="${_PC_GREEN}${staged}${_PC_RESET}/${_PC_YELLOW}${changed}${_PC_RESET}/${_PC_RED}${untracked}${_PC_RESET} "
            branch_color=$_PC_CYAN
        else
            ps1+="${_PC_GREEN}✓ "
            branch_color=$_PC_GREEN
        fi

        ps1+="${branch_color}${branch}${_PC_RESET} "
        (( ahead  > 0 )) && ps1+="(+${ahead}) "
        (( behind > 0 )) && ps1+="(-${behind}) "

        # Is the current directory ignored by git? (vendor/, build/, etc.)
        # `git check-ignore` does exactly this check; the old `git ls-files`
        # listed the whole repo and never matched the docstring's intent.
        if [[ $rel != "/" ]] && git check-ignore -q . 2>/dev/null; then
            ps1+="${_PC_RED}${rel}"
        else
            ps1+="${_PC_DIM}${rel}"
        fi
    else
        ps1+="${_PC_RESET}\w"
    fi

    PS1="${ps1} ${_PC_RESET}\$ "
}

if [[ "$PROMPT_COMMAND" != *render_prompt* ]]; then
    PROMPT_COMMAND="render_prompt; $PROMPT_COMMAND"
fi
render_prompt
