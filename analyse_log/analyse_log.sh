#!/bin/bash

OLD_IFS=$IFS

#get Current Dir
this_dir=$PWD
dirname $0|grep "^/" >/dev/null
if [ $? -eq 0 ];then
    this_dir=$(dirname $0)
else
    dirname $0|grep "^\." >/dev/null
    retval=$?
    if [ $retval -eq 0 ];then
        this_dir=$(dirname $0|sed "s#^.#$this_dir#")
    else
        this_dir=$(dirname $0|sed "s#^#$this_dir/#")
    fi
fi

cd $this_dir || exit

# 常量定义
LOG_PATH="${this_dir}/log"
DATA_PATH="${this_dir}/data"
ANALYSE_DIR="/data/proclog/log/squid/backup"
TOPIC="squid_log_analyse"
SALT="iysn6H1OM56sWHUp2rWLyFvabk3AhS0biwgvOuXL7UjwsmakX0RcaJ2L0XWmvFmx"

# 变量
host=`hostname`
node=`hostname | awk -F'-' '{print $1}' | sed 's#cdn##'`
yesterday=`date +%Y-%m-%d -d "-1 days"` 
fmt_yesterday=`date +%Y%m%d -d "-1 days"`
minute="${fmt_yesterday}21*"
#minute="${fmt_yesterday}2101*"
analyse_file="$ANALYSE_DIR/cache-access_custom.$host.$minute.log.gz"

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

makeRandom(){
    num=`echo ${RANDOM:0:2}`
    echo $(($num * 60))
}

function makeChecksum(){
    data=$1
    echo -ne "topic=$TOPIC&data=$data&salt=$SALT" | md5sum | awk '{print $1}'
}

function httpPost(){
    data=$1
    checksum=$2
    curl -d "topic=$TOPIC&data=$data&checksum=$checksum" "http://srequeue.ksyun.com"
}

init

log "starting to excute script: $0"

# 避免所有节点同时执行该脚本带来的压力，设置一个随机的sleep时间
sleep_time=`makeRandom`
sleep $sleep_time

url_num=`zcat $analyse_file | awk -F "\t" '{print $7}'| awk -F "?" '{print $1}' | sort | uniq | wc -l`
log "access url number: $url_num"

ts_time=`date +%s -d "$yesterday 21:00:00"`
json_data="{\"time\":\"${ts_time}000\", \"node\":\"$node\", \"host\":\"$host\", \"url_num\":$url_num}"

#
IFS="/"
checksum=`makeChecksum $json_data`
msg=`httpPost $json_data $checksum`
if [[ $msg == 'Success' ]];then
    log "send $json_data to kafka success"
else
    errorLog "send $json_data to kafka fail, error: $msg"
fi
IFS=$OLD_IFS
