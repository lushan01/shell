#!/bin/bash

TIME_INTERVAL=600 #second
BUFFER_LINE=100
TIME_20MIN_AGO=`date -d '-20 minute' +'%Y-%m-%d %H:%M:00'`
TIME_20MIN_AGO_TS=`date +%s -d "$TIME_20MIN_AGO"`
#TIME_20MIN_AGO_TS="1475251380"

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
mkdir -p data

function log(){
    echo "[$(date +"%Y/%m/%dT%H:%M:%S")] [SUCCESS] [$(hostname)] $*" >>access.log
}

function errorLog(){
    echo "[$(date +"%Y/%m/%dT%H:%M:%S")] [UPLOAD_LOG_CHECK_ERROR] [$(hostname)] $*" >>error.log
}

function fetalLog(){
    echo "[$(date +"%Y/%m/%dT%H:%M:%S")] [FETAL] [$(hostname)] $*" >>fetal.log
}

function monitor_changed_log(){
    #kcache-nginx
    echo '/data/proclog/log/kcache-nginx/access.log'
    echo '/data/proclog/log/kcache-nginx/access_kingsoft_v2.log'
    #squid
    echo '/data/proclog/log/squid/access_custom.log'
    echo '/data/proclog/log/squid/access_kingsoft_v1.log'
    echo '/data/proclog/log/squid/access_kingsoft_v2.log'
    #ats
    echo '/data/proclog/log/ats/access.log'
    echo '/data/proclog/log/ats/access_kingsoft_v1.log'
}

function monitor_log_v2(){
	echo '/Application/atslogcollect/successfilename'
	#echo '/Application/kc-ngxlogcollectsla/successfilename'
	echo '/Application/newlogcollect/successfilename'
	echo '/Application/ngxlogcollect/successfilename'
	echo '/Application/slalogcollect/successfilename'
	echo '/Application/ycloudlogcollect/successfilename'
}

function get_file_mod_timestamp(){
    file=$1
    if [[ -z $file ]];then
        echo 0
    fi
    if [[ ! -f $file ]];then
        echo 0
    fi
    stat -c %Y  $file  2> /dev/null
}

function checked_file_roll(){
    file=$1
    mod_ts=$(get_file_mod_timestamp $file)
    ((mod_ts=$mod_ts+0))
    if [[ $mod_ts -eq 0 ]];then
        fetalLog "cannot get modify time of $file"
    fi
    cur_ts=$(date +%s)
    ((max_ts=$mod_ts+$TIME_INTERVAL))
    if [[ $max_ts -le $cur_ts ]];then
        errorLog "$file do not roll"
    else
        log "$file is rolling"
    fi
}

function checked_file_upload(){
	file=$1
	latest=$(tail -n $BUFFER_LINE $file | awk -F '.' '{print substr($(NF-2),0,12)}'  | sort -n | tail -n 1)
    latest_ts=$(date -d "$(echo $latest|awk '{print substr($0,0,4)"-"substr($0,5,2)"-"substr($0,7,2)" "substr($0,9,2)":"substr($0,11,2)":00"}')" +%s)
	cur_ts=$(date +%s)
	((max_ts=$latest_ts+$TIME_INTERVAL))
	if [[ $max_ts -le $cur_ts ]];then
        errorLog "$file do not upload"
    else
        log "$file $latest is uploading"
    fi
}

function checked_file_repeated(){
	file=$1
	tail -n $BUFFER_LINE $file | awk -F '.' '{print substr($(NF-2),0,12)}'  | sort  | uniq -cd > data/repeated_file
        while read line
        do
            repeated_num=`echo $line | awk '{print $1}'`
            repeated_file=`echo $line | awk '{print $2}'`
	    if [[ $repeated_num -gt 1 ]];then
		errorLog "$file $repeated_file repeated upload ,num:$repeated_num"
	    else
		log "$file $repeated_file upload do not repeated upload"
	    fi
	done < data/repeated_file
}

function log_delay_upload_check(){
	file=$1
	for cnt in `seq 0 59`
	do
        	ts=$(($TIME_20MIN_AGO_TS-60*$cnt))
    		date_format=`date +'%Y%m%d%H%M' -d @$ts`
		grep -P "$date_format\d{2}" $file >/dev/null
		if [[ $? -ne 0 ]];then
			errorLog "$file $date_format may be delay uploaded"
		fi
	done
}

squid_proc_num=`ps -ef | grep -P "^squid"|grep -cv grep`
ats_proc_num=`ps -ef | grep -P "^ats"|grep -cv grep`

for file in $(monitor_changed_log);do
    if [[ $squid_proc_num -eq 0 ]];then
        echo $file | grep squid >/dev/null
        if [[ $? -eq 0 ]];then
            continue
        fi
    fi
    if [[ $ats_proc_num -eq 0 ]];then
        echo $file | grep ats >/dev/null
        if [[ $? -eq 0 ]];then
            continue
        fi
    fi
    checked_file_roll $file
done

for file in $(monitor_log_v2);do
    if [[ ! -f $file ]];then
        fetalLog "no such a file: $file"
        continue
    fi

    tmp_file=`echo $file | awk -F/ '{print $3}'`
    if [[ $squid_proc_num -gt 1 ]];then
        if [[ $tmp_file = "atslogcollect" ]];then
            continue
        fi
    fi

    if [[ $ats_proc_num -ge 1 ]];then
        if [[ $tmp_file = "newlogcollect" ]] || [[ $tmp_file = "slalogcollect" ]] || [[ $tmp_file = "ycloudlogcollect" ]] ;then
	    contiune
        fi
    fi

    checked_file_upload $file
    checked_file_repeated $file
    log_delay_upload_check $file
done
