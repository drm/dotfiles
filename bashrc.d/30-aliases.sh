alias x=startx
alias z=$HOME/work/zicht/z-installer/vendor/bin/z
alias c="php app/console"
function missing_trans()
{
    tail -400 app/logs/development.log  | grep -i 'translation not found' | awk -F ":" '{ print $5 }' | awk -F "," '{ print $1 }'
}

function f {
    find $1 -type f -exec grep $2 '{}' +
}

