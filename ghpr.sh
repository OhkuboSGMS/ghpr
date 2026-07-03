#!/bin/bash
# ghpr shell function wrapper
# This provides automatic cd to work directory after checkout

ghpr() {
  local pr_number repo

  # Subcommands that don't change the working directory are passed straight
  # through to the core script (no cd afterwards).
  if [ $# -ge 1 ] && { [ "$1" = "clean" ] || [ "$1" = "prune" ] \
       || [ "$1" = "update" ] || [ "$1" = "self-update" ] || [ "$1" = "upgrade" ]; }; then
    "$HOME/.local/bin/ghpr" "$@"
    return $?
  fi

  # 'create' clones + makes a new branch, then cd into the work dir (like a PR
  # checkout). Work dir naming must match create_branch() in the core script.
  if [ $# -ge 1 ] && [ "$1" = "create" ]; then
    "$HOME/.local/bin/ghpr" "$@" || return 1
    local c_repo="$2" c_branch="$3"
    c_repo="${c_repo%/}"
    c_repo="${c_repo%.git}"
    local c_repo_name="${c_repo##*/}"
    local c_branch_dir="${c_branch//\//-}"
    local c_work_dir="$HOME/work/prs/${c_repo_name}-${c_branch_dir}"
    if [ -d "$c_work_dir" ]; then
      cd "$c_work_dir" || {
        echo "Failed to cd to ${c_work_dir}"
        return 1
      }
    else
      echo "Work dir not found: ${c_work_dir}"
      return 1
    fi
    return 0
  fi

  # Parse arguments - support both URL and separate arguments
  if [ $# -eq 1 ]; then
    # Single argument - assume it's a GitHub PR URL
    local url="$1"
    if [[ "$url" =~ ^https?://github\.com/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
      # Extract repo and PR number from URL
      # Bash uses BASH_REMATCH, zsh uses match array
      if [ -n "$BASH_VERSION" ]; then
        repo="${BASH_REMATCH[1]}"
        pr_number="${BASH_REMATCH[2]}"
      else
        # zsh
        repo="${match[1]}"
        pr_number="${match[2]}"
      fi
    else
      echo "Error: Invalid GitHub PR URL format"
      echo "Expected: https://github.com/owner/repo/pull/<number>"
      echo ""
      echo "Usage:"
      echo "  ghpr <pr-number> <owner/repo>"
      echo "  ghpr <github-pr-url>"
      echo "  ghpr create <owner/repo|repo-url> <branch>"
      echo "  ghpr clean [--dry-run] [--yes]"
      echo "  ghpr update"
      echo ""
      echo "Examples:"
      echo "  ghpr 125 octocat/Hello-World"
      echo "  ghpr https://github.com/octocat/Hello-World/pull/125"
      echo "  ghpr create octocat/Hello-World feature/login"
      return 1
    fi
  elif [ $# -eq 2 ]; then
    # Two arguments - original format
    pr_number="$1"
    repo="$2"
  else
    echo "Usage:"
    echo "  ghpr <pr-number> <owner/repo>"
    echo "  ghpr <github-pr-url>"
    echo "  ghpr create <owner/repo|repo-url> <branch>"
    echo "  ghpr clean [--dry-run] [--yes]"
    echo "  ghpr update"
    echo ""
    echo "Examples:"
    echo "  ghpr 125 octocat/Hello-World"
    echo "  ghpr https://github.com/octocat/Hello-World/pull/125"
    echo "  ghpr create octocat/Hello-World feature/login"
    return 1
  fi

  # Execute main script
  "$HOME/.local/bin/ghpr" "$pr_number" "$repo" || return 1

  # Calculate work_dir using same logic as script and cd
  local base_dir="$HOME/work/prs"
  local repo_name="${repo##*/}"
  local work_dir="${base_dir}/${repo_name}-pr${pr_number}"

  if [ -d "$work_dir" ]; then
    cd "$work_dir" || {
      echo "Failed to cd to ${work_dir}"
      return 1
    }
  else
    echo "Work dir not found: ${work_dir}"
    return 1
  fi
}
