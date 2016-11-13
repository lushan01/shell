#!/bin/bash

#get Current Dir
this_dir=$(cd $(dirname $0);pwd)
cd $this_dir || exit

#
LOG_PATH="$this_dir/log"
DATA_PATH="$this_dir/data"

# 初始化目录
function init(){
    [[ -d $LOG_PATH ]] || mkdir -p $LOG_PATH
    [[ -d $DATA_PATH ]] || mkdir -p $DATA_PATH
}

function log(){
    echo "[$(date +"%Y/%m/%dT%H:%M:%S")] [SUCCESS] [$(hostname)] $*" >>log/access.log
}

function errorLog(){
    echo "[$(date +"%Y/%m/%dT%H:%M:%S")] [ERROR] [$(hostname)] $*" >>log/error.log
}

function check_and_clean(){
    file=$1
    if [[ -f $file ]];then
        > $file
        log "empty $file success"
    else
        errorLog "$file isn't file, exit execute"
        return 1
    fi
}

function find_and_clean(){
    path=$1
    name=$2
    empty=$3
    if [[ -z $path ]];then
        errorLog "path: $path is null, exit to execute function: find_and_clean"
        return 1
    fi

    if [[ ! -d $path ]];then
        errorLog "path: $path is not dir, exit to execute function: find_and_clean"
        return 2
    fi

    if [[ -z $name ]];then
        errorLog "file: $name is null, exit to execute function: find_and_clean"
        return 2
    fi

    if [[ -z $empty ]];then
        empty=0
    fi

    if [[ $empty -ne 1 ]];then
        log "starting to execute command: find $path -mtime +${find_expire} -type f -name \"$name\"  2>/dev/null | xargs rm -f"
        find $path -mtime +${find_expire} -type f -name "$name"  2>/dev/null | xargs rm -f
    else
        log "starting to execute command: find $path -mtime +${find_expire} -type f -name \"$name\"  2>/dev/null | xargs rm -f"
        find $path -mtime +${find_expire} -type f -name "$name"  2>/dev/null | xargs -i echo "> " {}
    fi
}

function clean_var_log(){
    find_and_clean '/var/log/' 'cron-20*'
    find_and_clean '/var/log/' 'maillog-20*'
    find_and_clean '/var/log/' 'messages-20*'
    find_and_clean '/var/log/' 'secure-20*'
    find_and_clean '/var/log/' 'spooler-20*'
    find_and_clean '/var/log/' 'wtmp-20*'
}

function clean_root(){
    clean_var_log
    check_and_clean '/var/spool/mail/root'
    check_and_clean '/var/lib/mlocate/mlocate.db'
    check_and_clean '/Application/multiping/log/multiping.log'
    check_and_clean '/Application/multiping/apps/ippingfilterclient/logs/start.log'
}

# 保留最新5个core文件，以供RD分析
function clean_core_file(){
    num=`ls -tr /data/coresave/core.* | wc -l`
    if [[ $num -gt 5 ]];then
        difference=$(($num - 5))
        log "starting to delete core files:"
        ls -tr /data/coresave/core.* | head -n $difference >>log/access.log
        ls -tr /data/coresave/core.* | head -n $difference | xargs rm -f
        log "finished to delete core files"
    else
        errorLog "core file num: $num < 5, exit to excute function: clean_core_file"
        return 1
    fi
}

function clean_app_log(){
    find_and_clean '/data/logs' '*.201*'
    find_and_clean '/data/logs' '*.log'
}

# 初始化目录结构
init

log "starting to execute the script: $0"

thresholdRate=70
rootRate=$(df -h / 2>/dev/null| tail -n 1 | awk '{print $(NF-1)+0}')
if [[ -z $rootRate ]];then
    errorLog "rootUsage = $rootRate, exit to execute the script: $0"
    exit
fi
if [[ $rootRate -ge $thresholdRate ]];then
    find_expire=3
    log "starting to execute the function: clean_root"
    clean_root
    log "finished to execute the function: clean_root"
else
    errorLog "rootUsage < $rootRate, exit to execute the script: $0"
    exit
fi

clean_core_file

#find_expire=15
#echo "===> clean app log <==="
#clean_app_log

log "finished to execute the script: $0"
