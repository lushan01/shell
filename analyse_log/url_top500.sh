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
TOPIC="squid_url_analyse"

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

# 脚本初始化
init

log "starting to excute script: $0"

# 避免所有节点同时执行该脚本带来的压力，设置一个随机的sleep时间
sleep_time=`makeRandom`
sleep $sleep_time

zcat $analyse_file | awk -F "\t" '{print $7}'| awk -F "?" '{print $1}' | sort | uniq -c | sort -nr | head -500  > data/data.txt.$fmt_yesterday

ts_time=`date +%s -d "$yesterday 21:00:00"`

json_data="["
while read line
do
    url_num=`echo $line | awk '{print $1}'`
    url=`echo $line | awk '{print $2}'`
    json_data="$json_data{\"time\":\"${ts_time}000\", \"node\":\"$node\", \"host\":\"$host\", \"url\":\"$url\", \"url_num\":$url_num},"
done <data/data.txt.$fmt_yesterday
json_data=`echo "$json_data]" | sed 's#,]#]#'`

echo $json_data >data/json.txt.$fmt_yesterday

./push -f data/json.txt.$fmt_yesterday -t $TOPIC

if [[ $? -eq 0 ]];then
    log "program: $0 send json data to kafka success"
else
    errorLog "program: $0 send json data to kafka fail"
fi
