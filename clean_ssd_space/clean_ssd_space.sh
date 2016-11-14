#!/bin/bash

. /etc/init.d/functions

#get Current Dir
this_dir=$(cd $(dirname $0);pwd)
cd $this_dir || exit

# 设置常量
LOG_PATH="$this_dir/log"
DATA_PATH="$this_dir/data"
SQUID_CONF_FILE="/usr/local/squid/etc/squid.conf"
THRESHOLD=98

# 初始化目录
function init(){
    [[ -d $LOG_PATH ]] || mkdir -p $LOG_PATH
    [[ -d $DATA_PATH ]] || mkdir -p $DATA_PATH
}

function log(){
    echo "[$(date +"%Y/%m/%dT%H:%M:%S")] [SUCCESS] [$(hostname)] $*" >>log/access.log
}

function errorLog(){
    echo "[$(date +"%Y/%m/%dT%H:%M:%S")] [ERROR] [$(hostname)] $*" >>log/access.log
}

# 判断当前时间是否在19:00:00至23:59:59时间段内,若在此时段，则返回0,否则返回1
function isTopTime(){
    local t1=`date +'%Y-%m-%d 19:00:00'`
    local t2=`date +'%Y-%m-%d 23:59:59'`
    local ts1=`date +%s -d "$t1"`
    local ts2=`date +%s -d "$t2"`
    local ts=`date +%s`
    if [[ $ts -ge $ts1 && $ts -le $ts2 ]];then
        return 0
    else
        return 1
    fi
}

# 判断squid是否启动，启动返回0，未启动返回1
function isSquidOn(){
    /bin/netstat -ntlp | grep 800 >/dev/null
    if [[ $? -eq 0 ]];then
        return 0
    else
        return 1
    fi
}

# 获取ssd磁盘使用率，若获取不到盘符则输出0
function getSsdUsage(){
    local ssd_dir=$1
    local ssd_ratio
    df -h | grep -P "$ssd_dir$" >/dev/null 2>&1
    if [[ $? -eq 0 ]];then
        ssd_ratio=$(df -h | grep -P "$ssd_dir$" | awk '{print $5}' | cut -d% -f1)
	log "ssd_dir: $ssd_dir, ssd_ratio: $ssd_ratio"
        echo $ssd_ratio
        return 0
    else
        errorLog "$ssd_dir is not exist"
        echo 0
        return 1
    fi
}

# 初始化目录结构
init

log "starting to execute the script: $0"

# 晚高峰19:00至23:59不执行清理命令
isTopTime
if [[ $? -eq 0 ]];then
    errorLog "now is in top time of service, exit to excute the script: $0"
    exit
fi

# 检测squid是否存活，端口宕倒退出执行
isSquidOn
if [[ $? -eq 1 ]];then
    errorLog "squid is dead, exit to excute the script: $0"
    exit
fi

# 判断squid配置文件是否存在，若不存在则退出
if [[ -f $SQUID_CONF_FILE ]];then
    arr_disk=($(grep cache_dir $SQUID_CONF_FILE | grep coss | awk -F/ '{print "/"$2"/"$3}' | sort | uniq))
else
    errorLog "$SQUID_CONF_FILE is not exist, exit to excute the script: $0"
    exit
fi

# 对小于阈值的ssd盘进行判断计数,只要一个ssd使用率大于阈值，则退出for循环，立即执行ssd磁盘清理程序
count=0
for((i=0; i<${#arr_disk[@]}; i++))
do
    ratio=`getSsdUsage ${arr_disk[$i]}`
    if [[ $ratio -ge $THRESHOLD ]];then
        break
    else
        count=$(($count+1))
        continue
    fi
done

if [[ $count -eq ${#arr_disk[@]} ]];then
    errorLog "Mismatch strategy, exit to excute the script: $0"
    exit
fi

# 执行清理ssd磁盘无效索引数据
log "excute to cmd: service squid swaplog"
service squid swaplog

log "finished to execute the script: $0"
