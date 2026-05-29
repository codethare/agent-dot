test -z "$PS1" && return
umask 077

[[ $- != *i* ]] && return

if [ -n "$BASH_VERSION" ]; then
    export PS1='\u@\h:\w\$ '
else
    if [ "$UID" -eq 0 ]; then
        export PROMPT='[%f%n@%m]:%$HOME%# '
    else
        export PROMPT='[%f%n@%m]:%$HOME\$ '
    fi
fi

alias dayDev='cd ~/gt/test/daybyday/ && pnpm dev'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias tree='exa --tree -alh --icons --color=always'
alias ls='ls -ltch --color=auto'
alias l='exa -h --icons --group-directories-first --color=always'
alias ll='l -l --time-style=long-iso'              # Better output than ls -l
alias lll='l -l --time-style=full-iso -s modified' # Show full timestamp
alias la='l -a'
alias lla='ll -a'
alias lls='ll -s size'
alias llas='lla -s size'
alias llla='lll -a'
alias tree='exa --tree -alh --icons --color=always'

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias :q="exit"

export LANG=en_US.UTF-8
export PS1="\u@\h:\W \n\$ "

export WLR_RENDERER_ALLOW_SOFTWARE=1

if test -d "$HOME/.bin"; then
  PATH="$HOME/.bin:$PATH"
fi

if test -d "$HOME/.bin/bwrap"; then
  PATH="$HOME/.bin/bwrap:$PATH"
fi

if test -d "$HOME/.local/share/mise/shims"; then
  PATH="$HOME/.local/share/mise/shims:$PATH"
fi

if test -d "$HOME/.local/bin"; then
  PATH="$HOME/.local/bin:$PATH"
fi

if test -d "$HOME/.bun/bin"; then
  PATH="$HOME/.bun/bin:$PATH"
fi

if test -d "$HOME/.claude/omc"; then
  PATH="$HOME/.claude/omc:$PATH"
fi

